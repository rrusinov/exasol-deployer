#!/usr/bin/env bash
# Health command implementation

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"
# shellcheck source=lib/health_internal.sh
source "$LIB_DIR/health_internal.sh"

readonly HEALTH_REQUIRED_SERVICES=(
    "c4.service"
    "c4_cloud_command.service"
    "exasol-admin-ui.service"
    "exasol-data-symlinks.service"
)

# Exit codes
readonly HEALTH_EXIT_HEALTHY=0
readonly HEALTH_EXIT_ISSUES=1

show_health_help() {
    cat <<'EOF'
Run connectivity and service health checks for a deployment.

The command verifies SSH reachability for every node, COS endpoints,
key systemd services installed by the c4 deployer, volume attachments,
and cluster state. Health checks run in parallel for faster execution
on large deployments.

With --update flag, also refreshes IP addresses in inventory/ssh_config/INFO.txt
and can correct deployment status from failure states to 'database_ready' if all
health checks pass and the cluster is confirmed to be operational.

Usage:
  exasol health [flags]

Flags:
  --deployment-dir <path>      Deployment directory (default: ".")
  --refresh-terraform          Run 'tofu refresh' to sync Terraform state
  --output-format <format>     Output format: text (default) or json
  --verbose                    Show detailed output
  --update                     Refresh IPs and correct deployment status if cluster is healthy
  --quiet                      Show only errors and final status
  --wait-for <status,timeout>  Wait until deployment reaches status with timeout
                               Format: status,timeout (e.g., database_ready,15m)
                               If timeout omitted, defaults to 15m
  -h, --help                   Show help

Wait-for Status Values:
  database_ready               Wait for database to be healthy and ready
  stopped                      Wait for cluster to be fully stopped

Timeout Formats:
  15m                          15 minutes
  1h                           1 hour
  60s                          60 seconds

Exit Codes:
  0  Health check passed without issues
  1  Health check detected issues or timeout reached

Examples:
  exasol health --deployment-dir ./my-deployment
  exasol health --deployment-dir ./my-deployment --output-format json
  exasol health --deployment-dir ./my-deployment --refresh-terraform
  exasol health --deployment-dir ./my-deployment --verbose
  exasol health --deployment-dir ./my-deployment --update
  exasol health --deployment-dir ./my-deployment --wait-for database_ready,15m
  exasol health --deployment-dir ./my-deployment --wait-for database_ready
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
    local deploy_dir="${5:-.}"  # Optional deploy_dir parameter

    local private_ip=""
    private_ip=$(ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" hostname -I 2>/dev/null | awk '{print $1}' || true)

    # Extract node index from host_name (e.g., "n11" -> 0, "n12" -> 1)
    local node_index
    if [[ "$host_name" =~ ^n([0-9]+)$ ]]; then
        node_index=$((BASH_REMATCH[1] - 11))
    else
        node_index=-1
    fi

    # Try to get public IP from tofu output first (works for all providers, including libvirt and isolated environments)
    local public_ip=""
    if [[ -n "$deploy_dir" ]] && [[ -d "$deploy_dir" ]] && [[ $node_index -ge 0 ]]; then
        if cd "$deploy_dir" 2>/dev/null; then
            public_ip=$(tofu output -json node_public_ips 2>/dev/null | jq -r ".[$node_index] // empty" 2>/dev/null || true)
            cd - >/dev/null 2>&1 || true
        fi
    fi

    # Clean up the result (remove any whitespace/newlines)
    public_ip=$(echo "$public_ip" | tr -d '\r\n' | xargs)

    # If tofu output failed or returned invalid data, fall back to cloud-specific metadata services
    if [[ ! "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Try cloud provider metadata services first (more reliable than ip.me)
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
        esac
        public_ip=$(echo "$public_ip" | tr -d '\r\n' | xargs)

        # If metadata services failed, try ip.me as last resort (may return incorrect IP for libvirt/NAT)
        if [[ ! "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            public_ip=$(ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" \
                "curl -s --max-time 3 ip.me 2>/dev/null" 2>/dev/null || true)
            public_ip=$(echo "$public_ip" | tr -d '\r\n' | xargs)
        fi
    fi

    # If still no valid public IP, fall back to private IP
    if [[ -z "$public_ip" || "$public_ip" == "not available" || ! "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        public_ip="$private_ip"
    fi

    echo "${private_ip:-}|${public_ip:-}"
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

# Load public IPs from local Terraform state (outputs.node_public_ips)
health_load_state_public_ips() {
    local deploy_dir="$1"
    local state_file="$deploy_dir/terraform.tfstate"

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    jq -r '.outputs.node_public_ips.value[]?' "$state_file" 2>/dev/null || return 1
}

health_check_cloud_metadata_aws() {
    local deploy_dir="$1"
    local issues_var="$2"
    local output_format="$3"
    # shellcheck disable=SC2178
    local -n issues_ref="$issues_var"

    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        [[ "$output_format" == "text" && "$verbosity" != "quiet" ]] && echo "    ⓘ Cloud metadata: AWS CLI not available (skipping instance count check)"
        return 0
    fi

    # Get deployment name from directory
    local deployment_name
    deployment_name=$(basename "$deploy_dir")

    # Test if AWS CLI has valid credentials/region by running a simple command
    if ! aws ec2 describe-instances --max-items 1 --output text >/dev/null 2>&1; then
        # AWS CLI failed - likely no credentials or region configured
        if [[ "$output_format" == "text" && "$verbosity" != "quiet" ]]; then
            echo "    ⓘ Cloud metadata: AWS credentials/region not configured (skipping instance count check)"
        fi
        return 0
    fi

    # Query AWS for instances with this deployment tag
    # First try with 'deployment' tag, then fall back to 'Name' tag
    local instance_count
    instance_count=$(aws ec2 describe-instances \
        --filters "Name=tag:deployment,Values=$deployment_name" "Name=instance-state-name,Values=running" \
        --query 'length(Reservations[*].Instances[*])' \
        --output text 2>/dev/null || echo "0")

    # If no instances found with 'deployment' tag, try 'Name' tag
    if [[ "$instance_count" == "0" || "$instance_count" == "None" ]]; then
        instance_count=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=*${deployment_name}*" "Name=instance-state-name,Values=running" \
            --query 'length(Reservations[*].Instances[*])' \
            --output text 2>/dev/null || echo "0")
    fi

    # Convert "None" to "0" (AWS CLI returns "None" when no results)
    [[ "$instance_count" == "None" ]] && instance_count="0"

    # If still 0, skip the check (instances might not have the expected tags)
    if [[ "$instance_count" == "0" ]]; then
        if [[ "$output_format" == "text" && "$verbosity" != "quiet" ]]; then
            echo "    ⓘ Cloud metadata: No instances found with tag 'deployment=$deployment_name' or 'Name=*${deployment_name}*' (skipping instance count check)"
        fi
        return 0
    fi

    # Get expected instance count from state
    local expected_count
    expected_count=$(health_get_expected_cluster_size "$deploy_dir")

    if [[ "$instance_count" != "unknown" && "$expected_count" != "unknown" && "$instance_count" != "$expected_count" ]]; then
        [[ "$output_format" == "text" ]] && echo "    ✗ Cloud metadata: Instance count mismatch (expected=$expected_count, found=$instance_count)"
        issues_ref+=("{\"type\": \"cloud_instance_count_mismatch\", \"expected\": $expected_count, \"actual\": $instance_count, \"severity\": \"warning\"}")
        return 1
    fi

    [[ "$output_format" == "text" ]] && echo "    ✓ Cloud metadata: OK (instances=$instance_count)"
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
        "bash -lc 'shopt -s nullglob; count=0; broken=\"\"; sizes=\"\"; for link in /dev/exasol_data_*; do [[ -e \"\$link\" ]] || continue; [[ \"\$link\" == *table ]] && continue; if [[ -L \"\$link\" ]]; then target=\$(readlink -f \"\$link\" 2>/dev/null); if [[ -n \"\$target\" && -e \"\$target\" ]]; then count=\$((count+1)); size=\$(lsblk -b -n -o SIZE \"\$target\" 2>/dev/null | head -1); if [[ -n \"\$size\" ]]; then size_gb=\$((size / 1024 / 1024 / 1024)); sizes=\"\${sizes}\${sizes:+,}\${size_gb}GB\"; fi; else broken=\"\$broken \$link\"; fi; fi; done; echo \"\$count|\$broken|\$sizes\"'" 2>/dev/null || echo "0||")

    local volume_count="${volume_info%%|*}"
    local rest="${volume_info#*|}"
    local broken_links="${rest%%|*}"
    local disk_sizes="${rest#*|}"

    if [[ -z "$volume_count" ]]; then
        volume_count=0
    fi

    if [[ "$volume_count" -eq 0 ]]; then
        echo "no_data_volumes|$host_name"
        issues_ref+=("{\"type\": \"no_data_volumes\", \"host\": \"$host_name\", \"severity\": \"warning\"}")
        return 1
    fi

    if [[ -n "$broken_links" && "$broken_links" != "$rest" ]]; then
        echo "broken_volume_symlink|$host_name|$broken_links"
        issues_ref+=("{\"type\": \"broken_volume_symlink\", \"host\": \"$host_name\", \"details\": \"$broken_links\", \"severity\": \"warning\"}")
        return 1
    fi

    echo "volume_ok|$volume_count|$disk_sizes"
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
    # Get unique stages from all nodes
    local stages
    stages=$(ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" \
        "sudo -u exasol c4 ps -e '.[].Instances.Configs | to_entries | map(.value.ground.boot_stage) | unique | join(\",\")' 2>/dev/null" 2>/dev/null || echo "")

    if [[ -z "$stages" ]]; then
        echo "cluster_state_unknown"
        return 0  # Don't count as failure - might not be fully deployed yet
    fi

    # Normalise output: remove quotes, collapse whitespace/newlines to commas, deduplicate, and drop empties
    stages=$(echo "$stages" | tr -d '"' | tr '\r\n' ',' | tr -d ' ' | sed 's/,,*/,/g; s/^,//; s/,$//')
    if [[ -n "$stages" ]]; then
        stages=$(printf "%s\n" "$stages" | tr ',' '\n' | sort -u | paste -sd ',' -)
    fi

    # Check if all nodes are at the same stage
    if [[ "$stages" == "d" ]]; then
        echo "cluster_stage_d"  # Database ready
    elif [[ "$stages" =~ ^(a|a1)(,(a|a1))*$ ]]; then
        echo "cluster_stage_a"  # Stopped (SSH reachable, c4 service not ready)
    elif [[ "$stages" =~ ^(b|b1)(,(b|b1))*$ ]]; then
        echo "cluster_stage_b"  # Boot stage
    elif [[ "$stages" == "c" ]]; then
        echo "cluster_stage_c"  # COS ready
    else
        echo "cluster_stage_mixed:$stages"  # Mixed stages across nodes
    fi
    return 0
}

# Perform all health checks for a single host (designed to run in parallel)
health_check_single_host() {
    local ssh_config="$1"
    local host_name="$2"
    local host_ip="$3"
    local ssh_timeout="$4"
    local cloud_provider="$5"
    local check_cluster_state="$6"  # "true" or "false"
    local result_dir="$7"
    local deploy_dir="${8:-.}"  # Optional deploy_dir parameter

    local result_file="${result_dir}/health_${host_name}_$$.tmp"
    local -a local_issues=()

    # Initialize result
    local ssh_ok="false"
    local cos_ssh_ok="false"
    local services_status=""
    local volume_status=""
    local cluster_status=""
    local private_ip=""
    local public_ip=""
    local port_8443_ok="false"
    local port_8563_ok="false"

    # SSH check
    if ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" true >/dev/null 2>&1; then
        ssh_ok="true"

        # COS SSH check
        if grep -Eq "^Host[[:space:]]+${host_name}-cos" "$ssh_config" >/dev/null 2>&1; then
            if ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "${host_name}-cos" true >/dev/null 2>&1; then
                cos_ssh_ok="true"
            else
                local_issues+=("{\"type\": \"cos_ssh_unreachable\", \"host\": \"$host_name-cos\", \"severity\": \"warning\"}")
            fi
        fi

        # Service checks
        local service_results=""
        for service in "${HEALTH_REQUIRED_SERVICES[@]}"; do
            if ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" sudo systemctl is-active "$service" >/dev/null 2>&1; then
                service_results="${service_results}${service}:active;"
            else
                service_results="${service_results}${service}:failed;"
                local_issues+=("{\"type\": \"service_failed\", \"host\": \"$host_name\", \"service\": \"$service\", \"severity\": \"critical\"}")
            fi
        done
        services_status="$service_results"

        # Volume check
        volume_status=$(health_check_volume_attachments "$ssh_config" "$host_name" "$ssh_timeout" local_issues "json")

        # Cluster state (only for designated host)
        if [[ "$check_cluster_state" == "true" ]]; then
            cluster_status=$(health_check_cluster_state "$ssh_config" "$host_name" "$ssh_timeout" local_issues "json")
        fi

        # Fetch IPs
        local ip_info
        ip_info=$(health_fetch_remote_ips "$ssh_config" "$host_name" "$ssh_timeout" "$cloud_provider" "$deploy_dir")
        IFS='|' read -r private_ip public_ip <<<"$ip_info"
        [[ -z "$public_ip" ]] && public_ip="$private_ip"

        # Port checks (if we have a public IP)
        if [[ -n "$public_ip" ]] && command -v timeout >/dev/null 2>&1; then
            # Admin UI check
            local curl_output
            curl_output=$(curl -sk --max-time 10 -o /dev/null -w "%{http_code}" "https://$public_ip:8443/" 2>/dev/null || echo "000")
            if [[ "$curl_output" != "000" ]]; then
                port_8443_ok="true"
            else
                local_issues+=("{\"type\": \"adminui_unreachable\", \"host\": \"$host_name\", \"severity\": \"warning\"}")
            fi

            # DB port check - test on localhost since DB listens on private IP
            # Try curl first (error JSON response means port is working!)
            local db_response
            db_response=$(ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" \
                "curl -sk --max-time 5 'https://localhost:8563/' 2>/dev/null" 2>/dev/null || echo "")
            if [[ -n "$db_response" ]] && [[ "$db_response" == *"status"* || "$db_response" == *"WebSocket"* || "$db_response" == *"error"* ]]; then
                port_8563_ok="true"
            else
                # Fallback to testing from localhost via SSH
                if ssh -F "$ssh_config" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$ssh_timeout" "$host_name" \
                    "timeout 3 bash -c 'cat < /dev/null > /dev/tcp/localhost/8563' 2>/dev/null" >/dev/null 2>&1; then
                    port_8563_ok="true"
                fi
            fi

            if [[ "$port_8563_ok" != "true" ]]; then
                local_issues+=("{\"type\": \"db_port_unreachable\", \"host\": \"$host_name\", \"severity\": \"warning\"}")
            fi
        fi
    else
        local_issues+=("{\"type\": \"ssh_unreachable\", \"host\": \"$host_name\", \"severity\": \"critical\"}")
    fi

    # Build JSON result
    local issues_json="[]"
    if [[ ${#local_issues[@]} -gt 0 ]]; then
        issues_json="[$(IFS=,; echo "${local_issues[*]}")]"
    fi

    cat > "$result_file" <<EOF
{
  "host": "$host_name",
  "ansible_host": "$host_ip",
  "ssh_ok": $ssh_ok,
  "cos_ssh_ok": $cos_ssh_ok,
  "services": "$services_status",
  "volume_status": "$volume_status",
  "cluster_status": "$cluster_status",
  "private_ip": "$private_ip",
  "public_ip": "$public_ip",
  "port_8443_ok": $port_8443_ok,
  "port_8563_ok": $port_8563_ok,
  "issues": $issues_json
}
EOF

    echo "$result_file"
}

cmd_health() {
    local deploy_dir="."
    local do_refresh_terraform="false"
    local output_format="text"
    local verbosity="normal"  # normal, verbose, quiet
    local do_update_metadata="false"
    local wait_for_status=""
    local wait_timeout="15m"



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
            --update)
                do_update_metadata="true"
                shift
                ;;
            --wait-for)
                # Parse comma-separated status,timeout format
                local wait_for_value="$2"
                if [[ "$wait_for_value" =~ ^([^,]+),(.+)$ ]]; then
                    wait_for_status="${BASH_REMATCH[1]}"
                    wait_timeout="${BASH_REMATCH[2]}"
                else
                    # Only status provided, use default timeout
                    wait_for_status="$wait_for_value"
                    wait_timeout="15m"
                fi
                shift 2
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

    # Handle --wait-for BEFORE acquiring lock and running checks
    # We need to define the internal health check function that can be called without locks
    if [[ -n "$wait_for_status" ]]; then
        # Convert timeout to seconds
        local timeout_seconds
        if [[ "$wait_timeout" =~ ^([0-9]+)m$ ]]; then
            timeout_seconds=$((BASH_REMATCH[1] * 60))
        elif [[ "$wait_timeout" =~ ^([0-9]+)h$ ]]; then
            timeout_seconds=$((BASH_REMATCH[1] * 3600))
        elif [[ "$wait_timeout" =~ ^([0-9]+)s$ ]]; then
            timeout_seconds="${BASH_REMATCH[1]}"
        elif [[ "$wait_timeout" =~ ^([0-9]+)$ ]]; then
            timeout_seconds="$wait_timeout"
        else
            die "Invalid timeout format: $wait_timeout (use format like 15m, 1h, 60s)"
        fi

        local start_time
        start_time=$(date +%s)
        local end_time=$((start_time + timeout_seconds))
        local check_interval=10
        local iteration=0

        log_info "Waiting for status '$wait_for_status' (timeout: $wait_timeout)..."
        log_info "Running health checks every $check_interval seconds..."
        log_info ""

        while true; do
            local current_time
            current_time=$(date +%s)

            if [[ $current_time -ge $end_time ]]; then
                # Timeout - run one final health check with full output
                log_error ""
                log_error "Timeout waiting for status '$wait_for_status' after $wait_timeout"
                log_error "Running final health check..."
                log_error ""

                # Continue to run the normal health check below (without --wait-for)
                # This will show the full diagnostic output
                break
            fi

            iteration=$((iteration + 1))
            log_info "Health check remaining time: $((end_time - current_time))s ..."

            # Wait for any existing health check lock to be released
            local lock_wait_seconds=0
            local max_lock_wait=60
            while lock_exists "$deploy_dir"; do
                local lock_op
                lock_op=$(lock_info "$deploy_dir" | jq -r '.operation // "unknown"' 2>/dev/null || echo "unknown")

                if [[ "$lock_op" == "health" ]]; then
                    # Another health check is running, wait for it
                    if [[ $lock_wait_seconds -ge $max_lock_wait ]]; then
                        log_warn "Health check lock held for ${max_lock_wait}s, proceeding anyway"
                        break
                    fi
                    sleep 1
                    lock_wait_seconds=$((lock_wait_seconds + 1))
                else
                    # Different operation is running, skip this iteration
                    log_warn "Operation '$lock_op' in progress, skipping health check iteration"
                    sleep "$check_interval"
                    continue 2  # Continue outer while loop
                fi
            done

            # Run the internal health check function (same as final check but quiet)
            # This function sets variables: overall_issues, ssh_passed, ssh_failed, cluster_status, etc.
            health_run_internal_checks "$deploy_dir" "quiet" "json" "$do_update_metadata" "$cloud_provider" 2>/dev/null || true

            # Determine current status from health check results
            local current_status
            current_status=$(health_determine_status "$deploy_dir" "$ssh_passed" "$ssh_failed" "$cluster_status" "$overall_issues" 2>/dev/null || echo "unknown")
            log_debug "Current status: $current_status (overall_issues=$overall_issues, cluster_status=$cluster_status, ssh_passed=$ssh_passed, ssh_failed=$ssh_failed)"

            # Update persistent state if --update flag is set and status changed
            if [[ "$do_update_metadata" == "true" && "$current_status" != "unknown" ]]; then
                local persistent_status
                persistent_status=$(state_get_status "$deploy_dir" 2>/dev/null || echo "unknown")

                if [[ "$persistent_status" != "$current_status" ]]; then
                    state_set_status "$deploy_dir" "$current_status"
                    log_debug "Status updated: $persistent_status -> $current_status"
                fi
            fi

            if [[ "$current_status" == "$wait_for_status" ]]; then
                # Success - run one final health check with full output
                log_info ""
                log_info "✓ Status reached: $wait_for_status"
                log_info "Running final health check..."
                log_info ""

                # Continue to run the normal health check below (without --wait-for)
                # This will show the full diagnostic output
                break
            fi

            # Check if we're in a failure state that won't recover
            case "$current_status" in
                *_failed)
                    # Failure - run one final health check with full output
                    log_error ""
                    log_error "Deployment is in failed state: $current_status"
                    log_error "Running final health check..."
                    log_error ""

                    # Continue to run the normal health check below (without --wait-for)
                    # This will show the full diagnostic output
                    break
                    ;;
            esac

            sleep "$check_interval"
        done

        # After the wait loop, continue with normal health check execution
        # This will perform one final health check and print the full report
    fi

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

    # Run internal health checks
    # This function sets all health check variables: overall_issues, ssh_passed, ssh_failed, 
    # cluster_status, cluster_ready, services_active, services_failed, json_issues, failed_checks, etc.
    health_run_internal_checks "$deploy_dir" "$verbosity" "$output_format" "$do_update_metadata" "$cloud_provider"

    # Terraform state refresh if requested
    if [[ "$do_refresh_terraform" == "true" ]]; then
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
{"timestamp": "$timestamp", "status": "$([ "$overall_issues" -eq 0 ] && echo healthy || echo unhealthy)", "issues_count": $overall_issues, "ssh_passed": $ssh_passed, "ssh_failed": $ssh_failed, "services_active": $services_active, "services_failed": $services_failed}
EOF
    )
    echo "$history_entry" >> "$history_file"

    local health_status="healthy"
    [[ "$overall_issues" -gt 0 ]] && health_status="unhealthy"
    state_update "$deploy_dir" "health_status" "$health_status"

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
    }
  },
  "issues_count": $overall_issues,
  "issues": $issues_json
}
EOF
    else
        # Text output
        echo "============================================================"
        if [[ "$overall_issues" -eq 0 ]]; then
            log_info "✓ Health check completed without issues."
        else
            log_error "✗ Health check detected ${overall_issues} issue(s)."

            # Print summary of failed checks
            if [[ ${#failed_checks[@]} -gt 0 ]]; then
                echo ""
                echo "Summary of Failed Checks:"
                echo "============================================================"
                for failed_check in "${failed_checks[@]}"; do
                    echo "  ✗ $failed_check"
                done
            fi
        fi
    fi

    # Remove lock
    lock_remove "$deploy_dir"

    # Determine exit code
    if [[ "$overall_issues" -eq 0 ]]; then
        return "$HEALTH_EXIT_HEALTHY"
    else
        return "$HEALTH_EXIT_ISSUES"
    fi
}
