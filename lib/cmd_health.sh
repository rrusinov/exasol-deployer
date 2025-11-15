#!/usr/bin/env bash
# Health command implementation

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"

readonly HEALTH_REQUIRED_SERVICES=(
    "c4.service"
    "c4_cloud_command.service"
    "exasol-admin-ui.service"
    "exasol-data-symlinks.service"
)

# Exit codes
readonly HEALTH_EXIT_HEALTHY=0
readonly HEALTH_EXIT_ISSUES=1
readonly HEALTH_EXIT_REMEDIATION_FAILED=2

show_health_help() {
    cat <<'EOF'
Run connectivity and service health checks for a deployment.

The command verifies SSH reachability for every node, COS endpoints,
key systemd services installed by the c4 deployer, and IP consistency
between live hosts and local metadata files. Optional flags allow the
command to update local metadata or attempt basic remediation.

Usage:
  exasol health [flags]

Flags:
  --deployment-dir <path>   Deployment directory (default: ".")
  --update                  Update inventory/ssh_config/INFO.txt when IPs change
  --try-fix                 Restart failed services automatically when possible
  --refresh-terraform       Run 'tofu refresh' to sync Terraform state
  --output-format <format>  Output format: text (default) or json
  --verbose                 Show detailed output
  --quiet                   Show only errors and final status
  -h, --help                Show help

Exit Codes:
  0  Health check passed without issues
  1  Health check detected issues
  2  Remediation attempted but failed

Examples:
  exasol health --deployment-dir ./my-deployment
  exasol health --deployment-dir ./my-deployment --update
  exasol health --deployment-dir ./my-deployment --try-fix
  exasol health --deployment-dir ./my-deployment --output-format json
  exasol health --deployment-dir ./my-deployment --update --refresh-terraform
  exasol health --deployment-dir ./my-deployment --verbose
EOF
}

health_require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        die "Required tool '$tool' is not installed or not in PATH"
    fi
}

health_get_expected_cluster_size() {
    local deploy_dir="$1"

    local cluster_size
    cluster_size=$(state_read "$deploy_dir" "cluster_size" 2>/dev/null || echo "")
    if [[ -z "$cluster_size" || "$cluster_size" == "null" ]]; then
        local tfvars_file="$deploy_dir/${VARS_FILE}"

        if [[ -f "$tfvars_file" ]]; then
            cluster_size=$(awk -F'=' '/^[[:space:]]*node_count[[:space:]]*=/{gsub(/[^0-9]/,"",$2); if($2!="") {print $2; exit}}' "$tfvars_file" 2>/dev/null)
        fi
    fi

    if [[ -z "$cluster_size" ]]; then
        cluster_size="unknown"
    fi

    echo "$cluster_size"
}

health_fetch_remote_ips() {
    local ssh_config="$1"
    local host_name="$2"
    local ssh_timeout="$3"
    local cloud_provider="$4"

    local private_ip=""
    private_ip=$(ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" hostname -I 2>/dev/null | awk '{print $1}' || true)

    local public_ip=""
    case "$cloud_provider" in
        aws)
            public_ip=$(ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" \
                "curl -s --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null" 2>/dev/null || true)
            ;;
        azure)
            public_ip=$(ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" \
                "curl -s -H Metadata:true --max-time 2 'http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text' 2>/dev/null" 2>/dev/null || true)
            ;;
        gcp)
            public_ip=$(ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" \
                "curl -s -H Metadata-Flavor:Google --max-time 2 'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip' 2>/dev/null" 2>/dev/null || true)
            ;;
        *)
            public_ip=""
            ;;
    esac

    public_ip=$(echo "$public_ip" | tr -d '\r')
    if [[ -z "$public_ip" || "$public_ip" == "not available" ]]; then
        public_ip="$private_ip"
    fi

    echo "${private_ip:-}|${public_ip:-}"
}

health_check_external_ports() {
    local public_ip="$1"
    local host_name="$2"
    local issues_var="$3"
    local output_format="$4"

    if [[ -z "$public_ip" ]]; then
        return 0
    fi

    # shellcheck disable=SC2178
    # shellcheck disable=SC2178
    # shellcheck disable=SC2178
    local -n issues_ref="$issues_var"
    local failures=0

    if ! command -v timeout >/dev/null 2>&1; then
        [[ "$output_format" == "text" ]] && echo "    Port checks skipped (timeout command unavailable)"
        return 0
    fi

    local curl_output
    curl_output=$(curl -sk --max-time 10 -o /dev/null -w "%{http_code}|%{content_type}" "https://$public_ip:8443/" 2>/dev/null || echo "000|")
    local http_code="${curl_output%%|*}"
    local content_type="${curl_output#*|}"
    if [[ "$http_code" != "000" ]]; then
        [[ "$output_format" == "text" ]] && echo "    Admin UI (8443): HTTPS $http_code (${content_type:-unknown})"
    else
        [[ "$output_format" == "text" ]] && echo "    Admin UI (8443): FAILED (no HTTPS response)"
        issues_ref+=("$(printf '{"type": "adminui_unreachable", "host": "%s", "severity": "warning"}' "$host_name")")
        failures=$((failures + 1))
    fi

    local db_ok="false"
    if command -v openssl >/dev/null 2>&1; then
        if timeout 5 openssl s_client -brief -connect "$public_ip:8563" < /dev/null >/dev/null 2>&1; then
            db_ok="true"
        fi
    else
        if timeout 5 bash -c "</dev/tcp/$public_ip/8563" >/dev/null 2>&1; then
            db_ok="true"
        fi
    fi

    if [[ "$db_ok" == "true" ]]; then
        [[ "$output_format" == "text" ]] && echo "    DB port (8563): reachable"
    else
        [[ "$output_format" == "text" ]] && echo "    DB port (8563): FAILED"
        issues_ref+=("$(printf '{"type": "db_port_unreachable", "host": "%s", "severity": "warning"}' "$host_name")")
        failures=$((failures + 1))
    fi

    return "$failures"
}

health_backup_file() {
    local file="$1"
    local deploy_dir="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    local backup_dir
    backup_dir="$deploy_dir/.backups/health/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir" || return 1

    local filename
    filename="$(basename "$file")"
    cp "$file" "$backup_dir/$filename" || return 1

    echo "$backup_dir/$filename"
    return 0
}

health_update_inventory_ip() {
    local inventory_file="$1"
    local host="$2"
    local new_ip="$3"

    if [[ ! -f "$inventory_file" ]]; then
        return 1
    fi

    # Use awk to update the inventory file
    local temp_file="${inventory_file}.tmp"

    awk -v host="$host" -v new_ip="$new_ip" '
    BEGIN { changed = 0 }
    {
        # Skip empty lines and comments
        if (NF == 0 || $0 ~ /^[[:space:]]*#/) {
            print $0
            next
        }

        # Check if this line starts with our host
        if ($1 == host) {
            # Process each field to find and update ansible_host
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^ansible_host=/) {
                    # Extract current IP
                    split($i, parts, "=")
                    if (parts[2] != new_ip) {
                        $i = "ansible_host=" new_ip
                        changed = 1
                    }
                }
            }
        }
        print $0
    }
    END { exit changed }
    ' "$inventory_file" > "$temp_file"

    if [[ $? -eq 1 ]]; then
        # awk returned 1, meaning file was changed
        mv "$temp_file" "$inventory_file"
        return 0
    else
        # No changes needed
        rm -f "$temp_file"
        return 1
    fi
}

health_update_ssh_config() {
    local ssh_config="$1"
    local host="$2"
    local new_ip="$3"

    if [[ ! -f "$ssh_config" ]]; then
        return 1
    fi

    # Use awk to update the SSH config file
    local temp_file="${ssh_config}.tmp"

    awk -v host="$host" -v new_ip="$new_ip" '
    BEGIN {
        current_host = ""
        changed = 0
    }
    {
        # Store original line
        original_line = $0

        # Skip empty lines - preserve them
        if (NF == 0 || $0 ~ /^[[:space:]]*$/) {
            print $0
            next
        }

        # Convert line to lowercase for comparison
        lower_line = tolower($0)

        # Check if this is a Host declaration
        if (lower_line ~ /^[[:space:]]*host[[:space:]]/) {
            # Extract host name (second field)
            split($0, parts)
            current_host = (length(parts) > 1) ? parts[2] : ""
            print $0
            next
        }

        # Check if we are in the target host section and this is a HostName line
        if ((current_host == host || current_host == host "-cos") &&
            lower_line ~ /^[[:space:]]*hostname[[:space:]]/) {
            # Extract current IP
            split($0, tokens)
            if (length(tokens) >= 2 && tokens[2] != new_ip) {
                # Update the IP while preserving indentation
                match($0, /^[[:space:]]*/)
                indent = substr($0, RSTART, RLENGTH)
                print indent "HostName " new_ip
                changed = 1
                next
            }
        }

        print $0
    }
    END { exit changed }
    ' "$ssh_config" > "$temp_file"

    if [[ $? -eq 1 ]]; then
        # awk returned 1, meaning file was changed
        mv "$temp_file" "$ssh_config"
        return 0
    else
        # No changes needed
        rm -f "$temp_file"
        return 1
    fi
}

health_update_info_file() {
    local info_file="$1"
    local old_ip="$2"
    local new_ip="$3"

    if [[ ! -f "$info_file" ]]; then
        return 1
    fi

    # Check if old_ip exists in the file
    if ! grep -qF "$old_ip" "$info_file"; then
        return 1  # unchanged
    fi

    # Replace old_ip with new_ip using sed
    local temp_file="${info_file}.tmp"
    sed "s/${old_ip}/${new_ip}/g" "$info_file" > "$temp_file"

    # Move the temp file to the original
    mv "$temp_file" "$info_file"
    return 0  # updated
}

health_check_cloud_metadata_aws() {
    local deploy_dir="$1"
    local issues_var="$2"
    local output_format="$3"
    # shellcheck disable=SC2178
    local -n issues_ref="$issues_var"

    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata check: AWS CLI not available, skipping"
        return 0
    fi

    # Get deployment name from directory
    local deployment_name
    deployment_name=$(basename "$deploy_dir")

    # Query AWS for instances with this deployment tag
    local instance_count
    if ! instance_count=$(aws ec2 describe-instances \
        --filters "Name=tag:deployment,Values=$deployment_name" "Name=instance-state-name,Values=running" \
        --query 'length(Reservations[].Instances[])' \
        --output text 2>/dev/null); then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata check: AWS CLI error, skipping"
        return 0
    fi

    # Get expected instance count from state
    local expected_count
    expected_count=$(health_get_expected_cluster_size "$deploy_dir")

    if [[ "$instance_count" != "unknown" && "$expected_count" != "unknown" && "$instance_count" != "$expected_count" ]]; then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata: Instance count mismatch (expected=$expected_count, found=$instance_count)"
        issues_ref+=("{\"type\": \"cloud_instance_count_mismatch\", \"expected\": $expected_count, \"actual\": $instance_count, \"severity\": \"critical\"}")
        return 1
    fi

    [[ "$output_format" == "text" ]] && echo "    Cloud metadata: OK (instances=$instance_count)"
    return 0
}

health_check_cloud_metadata_azure() {
    local deploy_dir="$1"
    local issues_var="$2"
    local output_format="$3"
    # shellcheck disable=SC2178
    local -n issues_ref="$issues_var"

    # Check if Azure CLI is available
    if ! command -v az >/dev/null 2>&1; then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata check: Azure CLI not available, skipping"
        return 0
    fi

    # Get deployment name and resource group from state
    local deployment_name
    deployment_name=$(basename "$deploy_dir")

    local resource_group
    resource_group=$(state_read "$deploy_dir" "resource_group" 2>/dev/null || echo "unknown")

    if [[ "$resource_group" == "unknown" ]]; then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata check: Resource group not found in state"
        return 0
    fi

    # Query Azure for running VMs
    local instance_count
    if ! instance_count=$(az vm list --resource-group "$resource_group" \
        --query "[?tags.deployment=='$deployment_name' && powerState=='VM running'] | length(@)" \
        --output tsv 2>/dev/null); then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata check: Azure CLI error, skipping"
        return 0
    fi

    # Get expected instance count from state
    local expected_count
    expected_count=$(health_get_expected_cluster_size "$deploy_dir")

    if [[ "$instance_count" != "unknown" && "$expected_count" != "unknown" && "$instance_count" != "$expected_count" ]]; then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata: Instance count mismatch (expected=$expected_count, found=$instance_count)"
        issues_ref+=("{\"type\": \"cloud_instance_count_mismatch\", \"expected\": $expected_count, \"actual\": $instance_count, \"severity\": \"critical\"}")
        return 1
    fi

    [[ "$output_format" == "text" ]] && echo "    Cloud metadata: OK (instances=$instance_count)"
    return 0
}

health_check_cloud_metadata_gcp() {
    local deploy_dir="$1"
    local issues_var="$2"
    local output_format="$3"
    # shellcheck disable=SC2178
    local -n issues_ref="$issues_var"

    # Check if gcloud is available
    if ! command -v gcloud >/dev/null 2>&1; then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata check: gcloud CLI not available, skipping"
        return 0
    fi

    # Get deployment name and project from state
    local deployment_name
    deployment_name=$(basename "$deploy_dir")

    local project
    project=$(state_read "$deploy_dir" "gcp_project" 2>/dev/null || echo "unknown")

    if [[ "$project" == "unknown" ]]; then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata check: GCP project not found in state"
        return 0
    fi

    # Query GCP for running instances
    local instance_count
    if ! instance_count=$(gcloud compute instances list \
        --project="$project" \
        --filter="labels.deployment=$deployment_name AND status=RUNNING" \
        --format="value(name)" 2>/dev/null | wc -l); then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata check: gcloud CLI error, skipping"
        return 0
    fi

    # Get expected instance count from state
    local expected_count
    expected_count=$(health_get_expected_cluster_size "$deploy_dir")

    if [[ "$instance_count" != "unknown" && "$expected_count" != "unknown" && "$instance_count" != "$expected_count" ]]; then
        [[ "$output_format" == "text" ]] && echo "    Cloud metadata: Instance count mismatch (expected=$expected_count, found=$instance_count)"
        issues_ref+=("{\"type\": \"cloud_instance_count_mismatch\", \"expected\": $expected_count, \"actual\": $instance_count, \"severity\": \"critical\"}")
        return 1
    fi

    [[ "$output_format" == "text" ]] && echo "    Cloud metadata: OK (instances=$instance_count)"
    return 0
}

health_check_cloud_metadata() {
    local deploy_dir="$1"
    local cloud_provider="$2"
    local issues_var="$3"
    local output_format="$4"

    case "$cloud_provider" in
        aws)
            health_check_cloud_metadata_aws "$deploy_dir" "$issues_var" "$output_format"
            ;;
        azure)
            health_check_cloud_metadata_azure "$deploy_dir" "$issues_var" "$output_format"
            ;;
        gcp)
            health_check_cloud_metadata_gcp "$deploy_dir" "$issues_var" "$output_format"
            ;;
        *)
            return 0
            ;;
    esac
}

health_check_volume_attachments() {
    local ssh_config="$1"
    local host_name="$2"
    local ssh_timeout="$3"
    # shellcheck disable=SC2178
    local -n issues_ref=$4
    local output_format="$5"

    local volume_info
    volume_info=$(ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" \
        "bash -lc 'shopt -s nullglob; count=0; broken=""; for link in /dev/exasol_data_*; do [[ -e \"\$link\" ]] || continue; [[ \"\$link\" == *table ]] && continue; if [[ -L \"\$link\" ]]; then target=\$(readlink -f \"\$link\" 2>/dev/null); if [[ -n \"\$target\" && -e \"\$target\" ]]; then count=\$((count+1)); else broken=\"\$broken \$link\"; fi; fi; done; echo \"\$count|\$broken\"'" 2>/dev/null || echo "0|")

    local volume_count="${volume_info%%|*}"
    local broken_links="${volume_info#*|}"

    if [[ -z "$volume_count" ]]; then
        volume_count=0
    fi

    if [[ "$volume_count" -eq 0 ]]; then
        [[ "$output_format" == "text" ]] && echo "    Volume check: WARNING - No exasol_data_* symlinks detected"
        issues_ref+=("{\"type\": \"no_data_volumes\", \"host\": \"$host_name\", \"severity\": \"warning\"}")
        return 1
    fi

    if [[ -n "$broken_links" && "$broken_links" != "$volume_info" ]]; then
        [[ "$output_format" == "text" ]] && echo "    Volume check: WARNING - Broken symlinks:${broken_links}"
        issues_ref+=("{\"type\": \"broken_volume_symlink\", \"host\": \"$host_name\", \"details\": \"$broken_links\", \"severity\": \"warning\"}")
        return 1
    fi

    [[ "$output_format" == "text" ]] && echo "    Volume check: OK ($volume_count disk(s) found)"
    return 0
}

health_check_cluster_state() {
    local ssh_config="$1"
    local host_name="$2"
    local ssh_timeout="$3"
    # shellcheck disable=SC2178
    local -n issues_ref=$4
    local output_format="$5"

    # Check if c4 is available and can report cluster status
    local cluster_check
    cluster_check=$(ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" \
        "cd /home/exasol/exasol-release 2>/dev/null && sudo -u exasol ./c4 cluster status 2>/dev/null | grep -c 'cluster is online'" 2>/dev/null || echo "0")

    if [[ "$cluster_check" == "0" ]]; then
        [[ "$output_format" == "text" ]] && echo "    Cluster state: Unable to verify (c4 cluster status unavailable)"
        return 0  # Don't count as failure - might not be fully deployed yet
    fi

    [[ "$output_format" == "text" ]] && echo "    Cluster state: OK (cluster online)"
    return 0
}

cmd_health() {
    local deploy_dir="."
    local do_update="false"
    local do_try_fix="false"
    local do_refresh_terraform="false"
    local output_format="text"
    local verbosity="normal"  # normal, verbose, quiet

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_health_help
                return 0
                ;;
            --deployment-dir)
                deploy_dir="$2"
                shift 2
                ;;
            --update)
                do_update="true"
                shift
                ;;
            --try-fix)
                do_try_fix="true"
                shift
                ;;
            --refresh-terraform)
                do_refresh_terraform="true"
                shift
                ;;
            --output-format)
                output_format="$2"
                if [[ "$output_format" != "text" && "$output_format" != "json" ]]; then
                    log_error "Invalid output format: $output_format (must be 'text' or 'json')"
                    return 1
                fi
                shift 2
                ;;
            --verbose)
                verbosity="verbose"
                shift
                ;;
            --quiet)
                verbosity="quiet"
                shift
                ;;
            *)
                log_error "Unknown option for health command: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$deploy_dir" ]]; then
        deploy_dir="."
    fi

    if [[ ! -d "$deploy_dir" ]]; then
        die "Deployment directory not found: $deploy_dir"
    fi

    health_require_tool "curl"

    local cloud_provider
    cloud_provider=$(state_read "$deploy_dir" "cloud_provider" 2>/dev/null || echo "unknown")

    # Check if another operation is in progress
    if lock_exists "$deploy_dir"; then
        local lock_op
        lock_op=$(lock_info "$deploy_dir" | jq -r '.operation // "unknown"' 2>/dev/null || echo "unknown")
        if [[ "$lock_op" != "health" ]]; then
            die "Another operation ($lock_op) is in progress. Wait for it to complete."
        fi
    fi

    # Acquire lock for health check
    if ! lock_create "$deploy_dir" "health"; then
        die "Failed to acquire lock for health check"
    fi

    # Ensure lock is removed on exit
    # shellcheck disable=SC2064
    trap "lock_remove '$deploy_dir'" EXIT INT TERM

    # Check deployment state
    local current_state
    current_state=$(state_get_status "$deploy_dir" 2>/dev/null || echo "unknown")
    if [[ "$current_state" != "database_ready" && "$current_state" != "database_connection_failed" ]]; then
        log_warn "Deployment is in state: $current_state (health check may be incomplete)"
    fi

    local inventory_file="$deploy_dir/inventory.ini"
    local ssh_config_file="$deploy_dir/ssh_config"

    if [[ ! -f "$inventory_file" ]]; then
        lock_remove "$deploy_dir"
        die "Missing inventory.ini in $deploy_dir"
    fi

    if [[ ! -f "$ssh_config_file" ]]; then
        lock_remove "$deploy_dir"
        die "Missing ssh_config in $deploy_dir"
    fi

    health_require_tool "ssh"

    local -a host_entries=()

    # Parse inventory file using awk to extract host entries
    if [[ -f "$inventory_file" ]]; then
        mapfile -t host_entries < <(awk '
        BEGIN { section = "" }
        {
            # Skip empty lines and comments
            if (NF == 0 || $0 ~ /^[[:space:]]*#/) {
                next
            }

            # Check for section headers
            if ($0 ~ /^\[.*\]$/) {
                # Extract section name
                match($0, /\[(.*)\]/, arr)
                section = arr[1]
                next
            }

            # Only process lines in the exasol_nodes section
            if (section != "exasol_nodes") {
                next
            }

            # Parse host entry
            host = $1
            ansible_host = ""

            # Find ansible_host parameter
            for (i = 2; i <= NF; i++) {
                if ($i ~ /^ansible_host=/) {
                    split($i, kv, "=")
                    ansible_host = kv[2]
                    break
                }
            }

            # Output in format: host|ansible_host
            print host "|" ansible_host
        }
        ' "$inventory_file")
    fi

    if [[ ${#host_entries[@]} -eq 0 ]]; then
        die "No hosts found in inventory.ini"
    fi

    # Progress tracking
    progress_start "health" "checks" "Running health checks"

    local ssh_timeout=10
    local overall_issues=0
    local remediation_attempted=false
    local remediation_failed=false
    local info_file="$deploy_dir/INFO.txt"
    local tfstate_file="$deploy_dir/terraform.tfstate"

    # Tracking for JSON output
    local -a json_issues=()
    local ssh_passed=0
    local ssh_failed=0
    local services_active=0
    local services_failed=0
    local ip_mismatches=0

    # Determine if we should show detailed output
    local show_details="true"
    [[ "$verbosity" == "quiet" && "$output_format" == "text" ]] && show_details="false"

    if [[ "$output_format" == "text" && "$verbosity" != "quiet" ]]; then
        echo "Health report for $deploy_dir"
        echo "============================================================"
    fi

    # Check cloud metadata (once per deployment, not per host)
    if ! health_check_cloud_metadata "$deploy_dir" "$cloud_provider" json_issues "$output_format"; then
        overall_issues=$((overall_issues + 1))
    fi

    local entry
    for entry in "${host_entries[@]}"; do
        IFS='|' read -r host_name host_ip <<<"$entry"
        host_name="${host_name//[[:space:]]/}"
        host_ip="${host_ip//[[:space:]]/}"

        if [[ -z "$host_name" ]]; then
            continue
        fi

        [[ "$output_format" == "text" && "$show_details" == "true" ]] && echo "- Host: $host_name (ansible_host=${host_ip:-unknown})"

        if ! ssh -F "$ssh_config_file" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" true >/dev/null 2>&1; then
            [[ "$output_format" == "text" ]] && echo "    SSH: FAILED (host unreachable)"
            overall_issues=$((overall_issues + 1))
            ssh_failed=$((ssh_failed + 1))
            json_issues+=("{\"type\": \"ssh_unreachable\", \"host\": \"$host_name\", \"severity\": \"critical\"}")
            continue
        else
            [[ "$output_format" == "text" ]] && echo "    SSH: OK"
            ssh_passed=$((ssh_passed + 1))
        fi

        if grep -Eq "^Host[[:space:]]+${host_name}-cos" "$ssh_config_file" >/dev/null 2>&1; then
            if ssh -F "$ssh_config_file" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "${host_name}-cos" true >/dev/null 2>&1; then
                [[ "$output_format" == "text" ]] && echo "    COS SSH (${host_name}-cos): OK"
            else
                [[ "$output_format" == "text" ]] && echo "    COS SSH (${host_name}-cos): FAILED"
                overall_issues=$((overall_issues + 1))
                json_issues+=("{\"type\": \"cos_ssh_unreachable\", \"host\": \"$host_name-cos\", \"severity\": \"warning\"}")
            fi
        fi

        local service
        for service in "${HEALTH_REQUIRED_SERVICES[@]}"; do
            if ssh -F "$ssh_config_file" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" sudo systemctl is-active "$service" >/dev/null 2>&1; then
                [[ "$output_format" == "text" ]] && echo "    Service $service: active"
                services_active=$((services_active + 1))
                continue
            fi

            if [[ "$do_try_fix" == "true" ]]; then
                remediation_attempted=true
                if ssh -F "$ssh_config_file" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" sudo systemctl restart "$service" >/dev/null 2>&1 && \
                   ssh -F "$ssh_config_file" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" sudo systemctl is-active "$service" >/dev/null 2>&1; then
                    [[ "$output_format" == "text" ]] && echo "    Service $service: restarted successfully"
                    services_active=$((services_active + 1))
                    continue
                else
                    remediation_failed=true
                fi
            fi

            [[ "$output_format" == "text" ]] && echo "    Service $service: FAILED"
            overall_issues=$((overall_issues + 1))
            services_failed=$((services_failed + 1))
            json_issues+=("{\"type\": \"service_failed\", \"host\": \"$host_name\", \"service\": \"$service\", \"severity\": \"critical\"}")
        done

        # Check volume attachments
        if ! health_check_volume_attachments "$ssh_config_file" "$host_name" "$ssh_timeout" json_issues "$output_format"; then
            overall_issues=$((overall_issues + 1))
        fi

        # Check cluster state (only check on first node to avoid redundancy)
        if [[ "$host_name" == "${host_entries[0]%%|*}" ]]; then
            if ! health_check_cluster_state "$ssh_config_file" "$host_name" "$ssh_timeout" json_issues "$output_format"; then
                overall_issues=$((overall_issues + 1))
            fi
        fi

        local ip_info remote_private_ip remote_public_ip
        ip_info=$(health_fetch_remote_ips "$ssh_config_file" "$host_name" "$ssh_timeout" "$cloud_provider")
        IFS='|' read -r remote_private_ip remote_public_ip <<<"$ip_info"
        [[ -z "$remote_public_ip" ]] && remote_public_ip="$remote_private_ip"

        if [[ -n "$remote_private_ip" && "$output_format" == "text" ]]; then
            echo "    Private IP: $remote_private_ip"
        fi

        if [[ -n "$remote_public_ip" && -n "$host_ip" && "$remote_public_ip" != "$host_ip" ]]; then
            ip_mismatches=$((ip_mismatches + 1))

            if [[ "$do_update" == "true" ]]; then
                # Backup files before modification
                local backup_inventory backup_ssh backup_info
                backup_inventory=$(health_backup_file "$inventory_file" "$deploy_dir")
                backup_ssh=$(health_backup_file "$ssh_config_file" "$deploy_dir")
                [[ -f "$info_file" ]] && backup_info=$(health_backup_file "$info_file" "$deploy_dir")

                if [[ "$output_format" == "text" ]]; then
                    [[ -n "$backup_inventory" ]] && echo "    Created backup: $backup_inventory"
                    [[ -n "$backup_ssh" ]] && echo "    Created backup: $backup_ssh"
                    [[ -n "$backup_info" ]] && echo "    Created backup: $backup_info"
                fi

                local updated_any="false"
                if health_update_inventory_ip "$inventory_file" "$host_name" "$remote_public_ip"; then
                    [[ "$output_format" == "text" ]] && echo "    Updated inventory.ini with host IP $remote_public_ip"
                    updated_any="true"
                fi
                if health_update_ssh_config "$ssh_config_file" "$host_name" "$remote_public_ip"; then
                    [[ "$output_format" == "text" ]] && echo "    Updated ssh_config entries for $host_name"
                    updated_any="true"
                fi
                if health_update_info_file "$info_file" "$host_ip" "$remote_public_ip"; then
                    [[ "$output_format" == "text" ]] && echo "    Updated INFO.txt with new IP address"
                    updated_any="true"
                fi
                if [[ "$updated_any" != "true" ]]; then
                    [[ "$output_format" == "text" ]] && echo "    IP changed to $remote_public_ip but local metadata already up to date"
                else
                    host_ip="$remote_public_ip"
                fi
            else
                [[ "$output_format" == "text" ]] && echo "    IP mismatch detected (inventory=$host_ip, live=$remote_public_ip) - run with --update to sync files"
                overall_issues=$((overall_issues + 1))
                json_issues+=("{\"type\": \"ip_mismatch\", \"host\": \"$host_name\", \"expected\": \"$host_ip\", \"actual\": \"$remote_public_ip\", \"severity\": \"warning\"}")
            fi

            if [[ -f "$tfstate_file" ]] && grep -q "$host_ip" "$tfstate_file"; then
                [[ "$output_format" == "text" ]] && echo "    Terraform note: terraform.tfstate still references $host_ip (run 'tofu refresh' to update)"
            fi
        fi

        if [[ -n "$host_ip" ]]; then
            health_check_external_ports "$host_ip" "$host_name" json_issues "$output_format"
            local port_failures=$?
            overall_issues=$((overall_issues + port_failures))
        fi
    done

    # Terraform state refresh if requested
    if [[ "$do_refresh_terraform" == "true" && "$ip_mismatches" -gt 0 ]]; then
        if [[ "$output_format" == "text" ]]; then
            echo ""
            echo "Running Terraform state refresh..."
        fi

        if [[ -d "$deploy_dir/terraform" ]] && command -v tofu >/dev/null 2>&1; then
            if (cd "$deploy_dir/terraform" && tofu refresh -auto-approve >/dev/null 2>&1); then
                [[ "$output_format" == "text" ]] && echo "Terraform state refreshed successfully"
            else
                [[ "$output_format" == "text" ]] && echo "WARNING: Terraform refresh failed"
                json_issues+=("{\"type\": \"terraform_refresh_failed\", \"severity\": \"warning\"}")
            fi
        else
            [[ "$output_format" == "text" ]] && echo "WARNING: Terraform directory or tofu command not found"
        fi
    fi

    # Update state with health check results
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    state_update "$deploy_dir" "last_health_check" "$timestamp"

    # Store health history
    local history_file="$deploy_dir/.health_history.jsonl"
    local history_entry
    history_entry=$(cat <<EOF
{"timestamp": "$timestamp", "status": "$([ $overall_issues -eq 0 ] && echo healthy || echo unhealthy)", "issues_count": $overall_issues, "ssh_passed": $ssh_passed, "ssh_failed": $ssh_failed, "services_active": $services_active, "services_failed": $services_failed}
EOF
    )
    echo "$history_entry" >> "$history_file"

    local health_status="healthy"
    [[ "$overall_issues" -gt 0 ]] && health_status="unhealthy"
    state_update "$deploy_dir" "health_status" "$health_status"

    # Progress tracking
    if [[ "$overall_issues" -eq 0 ]]; then
        progress_complete "health" "checks" "Health check completed successfully"
    else
        progress_fail "health" "checks" "Health check detected $overall_issues issue(s)"
    fi

    # Generate output based on format
    if [[ "$output_format" == "json" ]]; then
        # Build JSON issues array
        local issues_json="[]"
        if [[ ${#json_issues[@]} -gt 0 ]]; then
            issues_json="[$(IFS=,; echo "${json_issues[*]}")]"
        fi

        # Determine final status
        local final_status="healthy"
        local exit_code=$HEALTH_EXIT_HEALTHY
        if [[ "$overall_issues" -gt 0 ]]; then
            final_status="issues_detected"
            exit_code=$HEALTH_EXIT_ISSUES
        fi
        if [[ "$remediation_attempted" == "true" && "$remediation_failed" == "true" ]]; then
            final_status="remediation_failed"
            exit_code=$HEALTH_EXIT_REMEDIATION_FAILED
        fi

        # Output JSON
        cat <<EOF
{
  "status": "$final_status",
  "exit_code": $exit_code,
  "timestamp": "$timestamp",
  "deployment_dir": "$deploy_dir",
  "checks": {
    "ssh": {
      "passed": $ssh_passed,
      "failed": $ssh_failed
    },
    "services": {
      "active": $services_active,
      "failed": $services_failed
    },
    "ip_consistency": {
      "mismatches": $ip_mismatches
    }
  },
  "issues_count": $overall_issues,
  "issues": $issues_json,
  "remediation": {
    "attempted": $remediation_attempted,
    "failed": $remediation_failed
  }
}
EOF
    else
        # Text output
        echo "============================================================"
        if [[ "$overall_issues" -eq 0 ]]; then
            log_info "Health check completed without issues."
        else
            log_warn "Health check detected ${overall_issues} issue(s)."
        fi
    fi

    # Remove lock
    lock_remove "$deploy_dir"

    # Determine exit code
    if [[ "$overall_issues" -eq 0 ]]; then
        return "$HEALTH_EXIT_HEALTHY"
    elif [[ "$remediation_attempted" == "true" && "$remediation_failed" == "true" ]]; then
        return "$HEALTH_EXIT_REMEDIATION_FAILED"
    else
        return "$HEALTH_EXIT_ISSUES"
    fi
}
