#!/bin/bash
# Init command implementation

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/versions.sh"

# Init command
cmd_init() {
    local deploy_dir=""
    local db_version=""
    local cluster_size=1
    local instance_type=""
    local data_volume_size=100
    local db_password=""
    local adminui_password=""
    local owner="exasol-default"
    local aws_region="us-east-1"
    local aws_profile="default"
    local allowed_cidr="0.0.0.0/0"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deployment-dir)
                deploy_dir="$2"
                shift 2
                ;;
            --db-version)
                db_version="$2"
                shift 2
                ;;
            --cluster-size)
                cluster_size="$2"
                shift 2
                ;;
            --instance-type)
                instance_type="$2"
                shift 2
                ;;
            --data-volume-size)
                data_volume_size="$2"
                shift 2
                ;;
            --db-password)
                db_password="$2"
                shift 2
                ;;
            --adminui-password)
                adminui_password="$2"
                shift 2
                ;;
            --owner)
                owner="$2"
                shift 2
                ;;
            --aws-region)
                aws_region="$2"
                shift 2
                ;;
            --aws-profile)
                aws_profile="$2"
                shift 2
                ;;
            --allowed-cidr)
                allowed_cidr="$2"
                shift 2
                ;;
            --list-versions)
                log_info "Available database versions:"
                list_versions
                return 0
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Set defaults
    if [[ -z "$deploy_dir" ]]; then
        deploy_dir="$(pwd)"
    fi
    deploy_dir=$(validate_directory "$deploy_dir")

    if [[ -z "$db_version" ]]; then
        db_version=$(get_default_version)
        log_info "Using default version: $db_version"
    fi

    # Validate version
    if ! validate_version_format "$db_version"; then
        die "Invalid version format"
    fi

    if ! version_exists "$db_version"; then
        log_error "Version not found: $db_version"
        log_info "Available versions:"
        list_versions
        die "Please specify a valid version with --db-version"
    fi

    # Check if directory is already initialized
    if is_deployment_directory "$deploy_dir"; then
        die "Directory already initialized: $deploy_dir"
    fi

    # Get version configuration
    local architecture
    architecture=$(get_version_config "$db_version" "ARCHITECTURE")

    # Set default instance type if not provided
    if [[ -z "$instance_type" ]]; then
        instance_type=$(get_version_config "$db_version" "DEFAULT_INSTANCE_TYPE")
        log_info "Using default instance type: $instance_type"
    fi

    # Generate passwords if not provided
    if [[ -z "$db_password" ]]; then
        db_password=$(generate_password 16)
        log_info "Generated random database password"
    fi

    if [[ -z "$adminui_password" ]]; then
        adminui_password=$(generate_password 16)
        log_info "Generated random AdminUI password"
    fi

    log_info "Initializing deployment directory: $deploy_dir"
    log_info "  Database version: $db_version"
    log_info "  Architecture: $architecture"
    log_info "  Cluster size: $cluster_size"
    log_info "  Instance type: $instance_type"
    log_info "  Data volume size: ${data_volume_size}GB"

    # Create deployment directory
    ensure_directory "$deploy_dir"

    # Initialize state file
    state_init "$deploy_dir" "$db_version" "$architecture" || die "Failed to initialize state"

    # Create templates directory
    local templates_dir="$deploy_dir/.templates"
    ensure_directory "$templates_dir"

    # Copy Terraform/Tofu templates
    local script_root
    script_root="$(cd "$LIB_DIR/.." && pwd)"
    log_info "Copying deployment templates..."

    cp -r "$script_root/templates/terraform/"* "$templates_dir/" 2>/dev/null || true
    cp -r "$script_root/templates/ansible/"* "$templates_dir/" 2>/dev/null || true

    # Create Terraform files in deployment directory
    create_terraform_files "$deploy_dir" "$architecture"

    # Write variables file
    log_info "Creating variables file..."
    write_variables_file "$deploy_dir" \
        "aws_region=$aws_region" \
        "aws_profile=$aws_profile" \
        "instance_type=$instance_type" \
        "instance_architecture=$architecture" \
        "node_count=$cluster_size" \
        "data_volume_size=$data_volume_size" \
        "allowed_cidr=$allowed_cidr" \
        "owner=$owner"

    # Store passwords and deployment metadata securely
    local credentials_file="$deploy_dir/.credentials.json"

    # Get download URLs from version config
    local db_url c4_url db_working_copy
    db_url=$(get_version_config "$db_version" "DB_DOWNLOAD_URL")
    c4_url=$(get_version_config "$db_version" "C4_DOWNLOAD_URL")
    db_working_copy=$(get_version_config "$db_version" "DB_VERSION")

    cat > "$credentials_file" <<EOF
{
  "db_password": "$db_password",
  "adminui_password": "$adminui_password",
  "db_download_url": "$db_url",
  "c4_download_url": "$c4_url",
  "db_working_copy": "$db_working_copy",
  "created_at": "$(get_timestamp)"
}
EOF
    chmod 600 "$credentials_file"

    # Create README
    cat > "$deploy_dir/README.md" <<EOF
# Exasol Deployment

This directory contains a deployment configuration for Exasol database.

## Configuration

- **Database Version**: $db_version
- **Architecture**: $architecture
- **Cluster Size**: $cluster_size nodes
- **Instance Type**: $instance_type
- **Region**: $aws_region

## Credentials

Database and AdminUI credentials are stored in \`.credentials.json\` (protected file).

## Next Steps

1. Review and customize \`variables.auto.tfvars\` if needed
2. Run \`./exasol deploy --deployment-dir $deploy_dir\` to deploy
3. Run \`./exasol status --deployment-dir $deploy_dir\` to check status
4. Run \`./exasol destroy --deployment-dir $deploy_dir\` to tear down

## Important Files

- \`.exasol.json\` - Deployment state (do not modify)
- \`variables.auto.tfvars\` - Terraform variables
- \`.credentials.json\` - Passwords (keep secure)
- \`terraform.tfstate\` - Terraform state (created after deployment)
EOF

    log_info ""
    log_info "✅ Deployment directory initialized successfully!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review configuration in: $deploy_dir/variables.auto.tfvars"
    log_info "  2. Deploy with: exasol deploy --deployment-dir $deploy_dir"
    log_info ""
    log_info "Credentials saved to: $deploy_dir/.credentials.json"
}

# Create Terraform configuration files
create_terraform_files() {
    local deploy_dir="$1"
    local architecture="$2"

    # Create symbolic links to templates
    local templates_dir="$deploy_dir/.templates"

    ln -sf ".templates/main.tf" "$deploy_dir/main.tf"
    ln -sf ".templates/variables.tf" "$deploy_dir/variables.tf"
    ln -sf ".templates/outputs.tf" "$deploy_dir/outputs.tf"
    ln -sf ".templates/inventory.tftpl" "$deploy_dir/inventory.tftpl"

    log_debug "Created Terraform configuration files"
}
