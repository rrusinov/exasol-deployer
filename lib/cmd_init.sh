#!/bin/bash
# Init command implementation - Multi-cloud support

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/versions.sh"

# Supported cloud providers
declare -A SUPPORTED_PROVIDERS=(
    [aws]="Amazon Web Services"
    [azure]="Microsoft Azure"
    [gcp]="Google Cloud Platform"
    [hetzner]="Hetzner Cloud"
    [digitalocean]="DigitalOcean"
)

# Init command
cmd_init() {
    local deploy_dir=""
    local cloud_provider=""
    local db_version=""
    local cluster_size=1
    local instance_type=""
    local data_volume_size=100
    local data_volumes_per_node=1
    local root_volume_size=50
    local db_password=""
    local adminui_password=""
    local owner="exasol-default"
    local allowed_cidr="0.0.0.0/0"

    # AWS-specific variables
    local aws_region="us-east-1"
    local aws_profile="default"
    local aws_spot_instance=false

    # Azure-specific variables
    local azure_region="eastus"
    local azure_subscription=""
    local azure_spot_instance=false

    # GCP-specific variables
    local gcp_region="us-central1"
    local gcp_project=""
    local gcp_spot_instance=false

    # Hetzner-specific variables
    local hetzner_location="nbg1"
    local hetzner_token=""

    # DigitalOcean-specific variables
    local digitalocean_region="nyc3"
    local digitalocean_token=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deployment-dir)
                deploy_dir="$2"
                shift 2
                ;;
            --cloud-provider)
                cloud_provider="$2"
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
            --data-volumes-per-node)
                data_volumes_per_node="$2"
                shift 2
                ;;
            --root-volume-size)
                root_volume_size="$2"
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
            --allowed-cidr)
                allowed_cidr="$2"
                shift 2
                ;;
            # AWS-specific options
            --aws-region)
                aws_region="$2"
                shift 2
                ;;
            --aws-profile)
                aws_profile="$2"
                shift 2
                ;;
            --aws-spot-instance)
                aws_spot_instance=true
                shift
                ;;
            # Azure-specific options
            --azure-region)
                azure_region="$2"
                shift 2
                ;;
            --azure-subscription)
                azure_subscription="$2"
                shift 2
                ;;
            --azure-spot-instance)
                azure_spot_instance=true
                shift
                ;;
            # GCP-specific options
            --gcp-region)
                gcp_region="$2"
                shift 2
                ;;
            --gcp-project)
                gcp_project="$2"
                shift 2
                ;;
            --gcp-spot-instance)
                gcp_spot_instance=true
                shift
                ;;
            # Hetzner-specific options
            --hetzner-location)
                hetzner_location="$2"
                shift 2
                ;;
            --hetzner-token)
                hetzner_token="$2"
                shift 2
                ;;
            # DigitalOcean-specific options
            --digitalocean-region)
                digitalocean_region="$2"
                shift 2
                ;;
            --digitalocean-token)
                digitalocean_token="$2"
                shift 2
                ;;
            --list-versions)
                log_info "Available database versions:"
                list_versions
                return 0
                ;;
            --list-providers)
                log_info "Supported cloud providers:"
                for provider in "${!SUPPORTED_PROVIDERS[@]}"; do
                    log_info "  - $provider: ${SUPPORTED_PROVIDERS[$provider]}"
                done
                return 0
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Validate cloud provider
    if [[ -z "$cloud_provider" ]]; then
        log_error "Cloud provider is required"
        log_info "Usage: exasol init --cloud-provider <provider> [options]"
        log_info "Supported providers: ${!SUPPORTED_PROVIDERS[*]}"
        log_info "Use --list-providers to see all supported providers"
        return 1
    fi

    if [[ ! -v "SUPPORTED_PROVIDERS[$cloud_provider]" ]]; then
        log_error "Unsupported cloud provider: $cloud_provider"
        log_info "Supported providers: ${!SUPPORTED_PROVIDERS[*]}"
        return 1
    fi

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
        log_info "Using default instance type for AWS: $instance_type"
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
    log_info "  Cloud Provider: ${SUPPORTED_PROVIDERS[$cloud_provider]}"
    log_info "  Database version: $db_version"
    log_info "  Architecture: $architecture"
    log_info "  Cluster size: $cluster_size"
    log_info "  Data volume size: ${data_volume_size}GB"

    # Provider-specific information
    case "$cloud_provider" in
        aws)
            log_info "  AWS Region: $aws_region"
            log_info "  AWS Instance Type: $instance_type"
            log_info "  AWS Spot Instance: $aws_spot_instance"
            ;;
        azure)
            log_info "  Azure Region: $azure_region"
            log_info "  Azure Spot Instance: $azure_spot_instance"
            ;;
        gcp)
            log_info "  GCP Region: $gcp_region"
            log_info "  GCP Spot Instance: $gcp_spot_instance"
            ;;
        hetzner)
            log_info "  Hetzner Location: $hetzner_location"
            ;;
        digitalocean)
            log_info "  DigitalOcean Region: $digitalocean_region"
            ;;
    esac

    # Create deployment directory
    ensure_directory "$deploy_dir"

    # Initialize state file with cloud provider
    state_init "$deploy_dir" "$db_version" "$architecture" "$cloud_provider" || die "Failed to initialize state"

    # Create templates directory
    local templates_dir="$deploy_dir/.templates"
    ensure_directory "$templates_dir"

    # Copy provider-specific templates
    local script_root
    script_root="$(cd "$LIB_DIR/.." && pwd)"
    log_info "Copying deployment templates..."

    # First, copy common Terraform resources (SSH keys, random ID, cloud-init)
    # These go directly into .templates/ so provider templates can reference them
    # Note: common-variables.tf and common-outputs.tf are documentation only, not copied
    if [[ -d "$script_root/templates/terraform-common" ]]; then
        cp "$script_root/templates/terraform-common/common.tf" "$templates_dir/" 2>/dev/null || true
        log_debug "Copied common Terraform resources (common.tf)"
    fi

    # Then, copy cloud-provider-specific terraform templates
    if [[ -d "$script_root/templates/terraform-$cloud_provider" ]]; then
        cp -r "$script_root/templates/terraform-$cloud_provider/"* "$templates_dir/" 2>/dev/null || true
        log_debug "Copied cloud-specific templates for $cloud_provider"
    else
        log_error "No templates found for cloud provider: $cloud_provider"
        die "Templates directory templates/terraform-$cloud_provider does not exist"
    fi

    # Ansible templates are cloud-agnostic
    cp -r "$script_root/templates/ansible/"* "$templates_dir/" 2>/dev/null || true
    log_debug "Copied Ansible templates"

    # Create Terraform files in deployment directory
    create_terraform_files "$deploy_dir" "$architecture" "$cloud_provider"

    # Write variables file based on cloud provider
    log_info "Creating variables file..."
    write_provider_variables "$deploy_dir" "$cloud_provider" \
        "$aws_region" "$aws_profile" "$aws_spot_instance" \
        "$azure_region" "$azure_subscription" "$azure_spot_instance" \
        "$gcp_region" "$gcp_project" "$gcp_spot_instance" \
        "$hetzner_location" "$hetzner_token" \
        "$digitalocean_region" "$digitalocean_token" \
        "$instance_type" "$architecture" "$cluster_size" \
        "$data_volume_size" "$data_volumes_per_node" "$root_volume_size" \
        "$allowed_cidr" "$owner"

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
  "cloud_provider": "$cloud_provider",
  "created_at": "$(get_timestamp)"
}
EOF
    chmod 600 "$credentials_file"

    # Create README
    create_readme "$deploy_dir" "$cloud_provider" "$db_version" "$architecture" \
        "$cluster_size" "$instance_type" "$aws_region" "$azure_region" "$gcp_region"

    log_info ""
    log_info "✅ Deployment directory initialized successfully!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review configuration in: $deploy_dir/variables.auto.tfvars"
    log_info "  2. Deploy with: exasol deploy --deployment-dir $deploy_dir"
    log_info ""
    log_info "Credentials saved to: $deploy_dir/.credentials.json"
}

# Write provider-specific variables
write_provider_variables() {
    local deploy_dir="$1"
    local cloud_provider="$2"
    local aws_region="$3"
    local aws_profile="$4"
    local aws_spot_instance="$5"
    local azure_region="$6"
    local azure_subscription="$7"
    local azure_spot_instance="$8"
    local gcp_region="$9"
    local gcp_project="${10}"
    local gcp_spot_instance="${11}"
    local hetzner_location="${12}"
    local hetzner_token="${13}"
    local digitalocean_region="${14}"
    local digitalocean_token="${15}"
    local instance_type="${16}"
    local architecture="${17}"
    local cluster_size="${18}"
    local data_volume_size="${19}"
    local data_volumes_per_node="${20}"
    local root_volume_size="${21}"
    local allowed_cidr="${22}"
    local owner="${23}"

    case "$cloud_provider" in
        aws)
            write_variables_file "$deploy_dir" \
                "aws_region=$aws_region" \
                "aws_profile=$aws_profile" \
                "instance_type=$instance_type" \
                "instance_architecture=$architecture" \
                "node_count=$cluster_size" \
                "data_volume_size=$data_volume_size" \
                "data_volumes_per_node=$data_volumes_per_node" \
                "root_volume_size=$root_volume_size" \
                "allowed_cidr=$allowed_cidr" \
                "owner=$owner" \
                "enable_spot_instances=$aws_spot_instance"
            ;;
        azure)
            write_variables_file "$deploy_dir" \
                "azure_region=$azure_region" \
                "azure_subscription=$azure_subscription" \
                "instance_type=$instance_type" \
                "instance_architecture=$architecture" \
                "node_count=$cluster_size" \
                "data_volume_size=$data_volume_size" \
                "data_volumes_per_node=$data_volumes_per_node" \
                "root_volume_size=$root_volume_size" \
                "allowed_cidr=$allowed_cidr" \
                "owner=$owner" \
                "enable_spot_instances=$azure_spot_instance"
            ;;
        gcp)
            write_variables_file "$deploy_dir" \
                "gcp_region=$gcp_region" \
                "gcp_project=$gcp_project" \
                "instance_type=$instance_type" \
                "instance_architecture=$architecture" \
                "node_count=$cluster_size" \
                "data_volume_size=$data_volume_size" \
                "data_volumes_per_node=$data_volumes_per_node" \
                "root_volume_size=$root_volume_size" \
                "allowed_cidr=$allowed_cidr" \
                "owner=$owner" \
                "enable_spot_instances=$gcp_spot_instance"
            ;;
        hetzner)
            write_variables_file "$deploy_dir" \
                "hetzner_location=$hetzner_location" \
                "hetzner_token=$hetzner_token" \
                "server_type=$instance_type" \
                "instance_architecture=$architecture" \
                "node_count=$cluster_size" \
                "data_volume_size=$data_volume_size" \
                "data_volumes_per_node=$data_volumes_per_node" \
                "root_volume_size=$root_volume_size" \
                "allowed_cidr=$allowed_cidr" \
                "owner=$owner"
            ;;
        digitalocean)
            write_variables_file "$deploy_dir" \
                "digitalocean_region=$digitalocean_region" \
                "digitalocean_token=$digitalocean_token" \
                "droplet_size=$instance_type" \
                "instance_architecture=$architecture" \
                "node_count=$cluster_size" \
                "data_volume_size=$data_volume_size" \
                "data_volumes_per_node=$data_volumes_per_node" \
                "root_volume_size=$root_volume_size" \
                "allowed_cidr=$allowed_cidr" \
                "owner=$owner"
            ;;
    esac
}

# Create README
create_readme() {
    local deploy_dir="$1"
    local cloud_provider="$2"
    local db_version="$3"
    local architecture="$4"
    local cluster_size="$5"
    local instance_type="$6"
    local aws_region="$7"
    local azure_region="$8"
    local gcp_region="$9"

    local region_info=""
    case "$cloud_provider" in
        aws) region_info="AWS Region: $aws_region" ;;
        azure) region_info="Azure Region: $azure_region" ;;
        gcp) region_info="GCP Region: $gcp_region" ;;
    esac

    cat > "$deploy_dir/README.md" <<EOF
# Exasol Deployment

This directory contains a deployment configuration for Exasol database.

## Configuration

- **Cloud Provider**: ${SUPPORTED_PROVIDERS[$cloud_provider]}
- **Database Version**: $db_version
- **Architecture**: $architecture
- **Cluster Size**: $cluster_size nodes
- **Instance Type**: $instance_type
- **$region_info**

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
}

# Create Terraform configuration files
create_terraform_files() {
    local deploy_dir="$1"
    local architecture="$2"
    local cloud_provider="$3"

    # Create symbolic links to templates
    local templates_dir="$deploy_dir/.templates"

    ln -sf ".templates/main.tf" "$deploy_dir/main.tf"
    ln -sf ".templates/variables.tf" "$deploy_dir/variables.tf"
    ln -sf ".templates/outputs.tf" "$deploy_dir/outputs.tf"

    # Inventory template may be cloud-specific
    if [[ -f "$templates_dir/inventory-$cloud_provider.tftpl" ]]; then
        ln -sf ".templates/inventory-$cloud_provider.tftpl" "$deploy_dir/inventory.tftpl"
    else
        ln -sf ".templates/inventory.tftpl" "$deploy_dir/inventory.tftpl"
    fi

    log_debug "Created Terraform configuration files for $cloud_provider"
}
