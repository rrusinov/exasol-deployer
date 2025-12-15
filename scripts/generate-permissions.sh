#!/usr/bin/env bash
# Generate permissions tables for cloud providers

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"

# Supported cloud providers
PROVIDERS=("aws" "azure" "gcp" "hetzner" "digitalocean" "exoscale" "libvirt")

# Create permissions directory
PERMISSIONS_DIR="$LIB_DIR/permissions"
ensure_directory "$PERMISSIONS_DIR"

# Create log directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$SCRIPT_DIR/tmp"
ensure_directory "$LOG_DIR"
LOG_FILE="$LOG_DIR/generate_permissions.log"

log_info "Logging to: $LOG_FILE"
echo "=== Permission Generation Log - $(date) ===" > "$LOG_FILE"

# Check for pike, podman, or docker
check_pike_availability() {
    if command -v pike >/dev/null 2>&1; then
        echo "pike"
    elif command -v podman >/dev/null 2>&1; then
        echo "podman"
    elif command -v docker >/dev/null 2>&1; then
        echo "docker"
    else
        log_error "Pike tool not found. Install pike, podman, or docker."
        log_error "  Install pike: go install github.com/jameswoolfenden/pike@latest"
        log_error "  Or use podman: podman pull jameswoolfenden/pike:latest"
        log_error "  Or use docker: docker pull jameswoolfenden/pike:latest"
        return 1
    fi
}

# Run pike scan
run_pike_scan() {
    local templates_dir="$1"
    local pike_mode="$2"
    
    if [[ "$pike_mode" == "pike" ]]; then
        pike scan -d "$templates_dir" -o json 2>/dev/null || true
    elif [[ "$pike_mode" == "podman" ]]; then
        podman run --rm -v "$templates_dir:/data" jameswoolfenden/pike:latest scan -d /data -o json 2>&1 || true
    elif [[ "$pike_mode" == "docker" ]]; then
        docker run --rm -v "$templates_dir:/data" jameswoolfenden/pike:latest scan -d /data -o json 2>/dev/null || true
    fi
}

# Detect pike availability
pike_mode=$(check_pike_availability)
if [[ -z "$pike_mode" ]]; then
    exit 1
fi

log_info "Using $pike_mode for permission analysis"

# Generate permissions for each provider
for provider in "${PROVIDERS[@]}"; do
    log_info "Generating permissions for $provider..."

    # Create temporary directory (unique for each provider)
    tmp_dir=$(mktemp -d)
    
    # Create credentials directory outside of deployment dir
    creds_dir=$(mktemp -d)

    # Initialize deployment with minimal config
    # Skip credential validation for permission generation
    case "$provider" in
        hetzner)
            init_args="--hetzner-token dummy-token"
            ;;
        digitalocean)
            init_args="--digitalocean-token dummy-token"
            ;;
        azure)
            # Create dummy Azure credentials file (outside deployment dir)
            azure_creds="$creds_dir/.azure_credentials"
            cat > "$azure_creds" <<EOF
{
  "appId": "00000000-0000-0000-0000-000000000000",
  "password": "dummy-password",
  "tenant": "00000000-0000-0000-0000-000000000000",
  "subscriptionId": "00000000-0000-0000-0000-000000000000"
}
EOF
            init_args="--azure-credentials-file $azure_creds --azure-subscription 00000000-0000-0000-0000-000000000000"
            ;;
        gcp)
            # Create dummy GCP credentials file (outside deployment dir)
            gcp_creds="$creds_dir/.gcp_credentials.json"
            cat > "$gcp_creds" <<EOF
{
  "type": "service_account",
  "project_id": "dummy-project",
  "client_email": "dummy@dummy.iam.gserviceaccount.com",
  "private_key_id": "dummy",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC\n-----END PRIVATE KEY-----\n"
}
EOF
            init_args="--gcp-credentials-file $gcp_creds --gcp-project dummy-project"
            ;;
        *)
            init_args=""
            ;;
    esac

    # shellcheck disable=SC2086
    if ! "$LIB_DIR/../exasol" init \
        --cloud-provider "$provider" \
        --deployment-dir "$tmp_dir" \
        --db-password dummy \
        --adminui-password dummy \
        --host-password dummy \
        $init_args >>"$LOG_FILE" 2>&1; then
        log_error "Failed to initialize deployment for $provider (check $LOG_FILE for details)"
        echo "=== Init failed for $provider ===" >> "$LOG_FILE"
        rm -rf "$tmp_dir"
        continue
    fi

    # Run pike on the deployment directory (not just templates)
    # Pike needs to see the actual terraform files that reference the templates
    if [[ -d "$tmp_dir" ]]; then
        # Run tofu init first so pike can analyze the full configuration
        cd "$tmp_dir" || continue
        echo "=== Running tofu init for $provider ===" >> "$LOG_FILE"
        if tofu init -backend=false >>"$LOG_FILE" 2>&1; then
            log_debug "Initialized terraform for $provider"
        else
            log_warn "Could not initialize terraform for $provider, proceeding anyway (check $LOG_FILE)"
        fi
        cd - >/dev/null || exit

        # Run pike scan
        echo "=== Running pike scan for $provider ===" >> "$LOG_FILE"
        pike_output=$(run_pike_scan "$tmp_dir" "$pike_mode")
        echo "$pike_output" >> "$LOG_FILE"

        # Store permissions in standardized JSON format for easy comparison
        if [[ -n "$pike_output" ]] && [[ ! "$pike_output" =~ "failed to get policy" ]]; then
            if echo "$pike_output" | jq . >/dev/null 2>&1; then
                # Already valid JSON (AWS)
                case "$provider" in
                    aws)
                        # Extract just the Action array for easier comparison
                        echo "$pike_output" | jq '{provider: "aws", permissions: .Statement[0].Action}' > "$PERMISSIONS_DIR/$provider.json"
                        ;;
                    *)
                        # Save as-is
                        echo "$pike_output" | jq . > "$PERMISSIONS_DIR/$provider.json"
                        ;;
                esac
                log_info "✅ Permissions generated for $provider (JSON format)"
            else
                # Convert HCL to JSON by extracting permissions list
                case "$provider" in
                    azure)
                        # Extract Azure actions from HCL
                        permissions=$(echo "$pike_output" | grep -A 500 'actions = \[' | grep -E '^\s*"Microsoft\.' | sed 's/[",]//g' | sed 's/^\s*//' | jq -R . | jq -s .)
                        echo "{\"provider\": \"azure\", \"permissions\": $permissions}" | jq . > "$PERMISSIONS_DIR/$provider.json"
                        ;;
                    gcp)
                        # Extract GCP permissions from HCL
                        permissions=$(echo "$pike_output" | grep -A 500 'permissions = \[' | grep -E '^\s*"' | grep -v 'permissions = \[' | sed 's/[",]//g' | sed 's/^\s*//' | jq -R . | jq -s .)
                        echo "{\"provider\": \"gcp\", \"permissions\": $permissions}" | jq . > "$PERMISSIONS_DIR/$provider.json"
                        ;;
                    *)
                        # Fallback: save HCL as .txt
                        echo "$pike_output" > "$PERMISSIONS_DIR/$provider.txt"
                        ;;
                esac
                log_info "✅ Permissions generated for $provider (JSON format)"
            fi
        else
            # Provider not supported by pike or error occurred
            not_applicable_msg="This cloud provider uses API tokens for authentication and does not have IAM-style permissions."
            case "$provider" in
                hetzner|digitalocean)
                    echo "$not_applicable_msg" > "$PERMISSIONS_DIR/$provider.txt"
                    log_info "ℹ️  $provider uses token-based authentication (no IAM permissions needed)"
                    ;;
                libvirt)
                    echo "This is a local deployment using libvirt/KVM and does not require cloud permissions." > "$PERMISSIONS_DIR/$provider.txt"
                    log_info "ℹ️  libvirt is local deployment (no cloud permissions needed)"
                    ;;
                *)
                    echo '{"error": "Could not generate permissions", "provider": "'"$provider"'"}' > "$PERMISSIONS_DIR/$provider.json"
                    log_warn "No valid permissions output for $provider (created placeholder)"
                    ;;
            esac
        fi
    else
        log_error "Deployment directory not found for $provider"
    fi

    # Clean up this provider's temp directory and credentials
    rm -rf "$tmp_dir"
    rm -rf "$creds_dir"
done

log_info "Permission generation complete"
log_info "Results stored in: $PERMISSIONS_DIR"
log_info "Logs saved to: $LOG_FILE"