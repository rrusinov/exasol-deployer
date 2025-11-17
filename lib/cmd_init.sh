#!/usr/bin/env bash
# Init command implementation - Multi-cloud support

# Source dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"
# shellcheck source=lib/versions.sh
source "$LIB_DIR/versions.sh"

# Supported cloud providers
declare -A SUPPORTED_PROVIDERS=(
    [aws]="Amazon Web Services"
    [azure]="Microsoft Azure"
    [gcp]="Google Cloud Platform"
    [hetzner]="Hetzner Cloud"
    [digitalocean]="DigitalOcean"
    [libvirt]="Local libvirt/KVM deployment"
)

# Normalize checksum values (strip algorithm prefix like "sha256:")
normalize_checksum_value() {
    local value="${1:-}"

    if [[ -z "$value" ]]; then
        echo ""
        return
    fi

    local normalized="${value#*:}"
    if [[ "${value,,}" == sha256:* ]]; then
        echo "$normalized"
    else
        echo "$value"
    fi
}

# Show help for init command
show_init_help() {
    cat <<'EOF'
Initialize a new deployment directory.

Usage:
  exasol init --cloud-provider <provider> [flags]

Required Flags:
  --cloud-provider <string>      Cloud provider: aws, azure, gcp, hetzner, digitalocean, libvirt

Common Flags:
  --deployment-dir <path>        Directory to store deployment files (default: ".")
  --db-version <version>         Database version (format: X.Y.Z-ARCH)
  --list-versions                List all available database versions
  --list-providers               List all supported cloud providers
  --cluster-size <n>             Number of nodes in the cluster (default: 1)
  --instance-type <type>         Instance/VM type (auto-detected if not specified)
  --data-volume-size <gb>        Data volume size in GB (default: 100)
  --data-volumes-per-node <n>    Data volumes per node (default: 1)
  --root-volume-size <gb>        Root volume size in GB (default: 50)
  --db-password <password>       Database password (random if not specified)
  --adminui-password <password>  Admin UI password (random if not specified)
  --owner <tag>                  Owner tag for resources (default: "exasol-deployer")
  --allowed-cidr <cidr>          CIDR allowed to access cluster (default: "0.0.0.0/0")
  -h, --help                     Show help

AWS-Specific Flags:
  --aws-region <region>          AWS region (default: "us-east-1")
  --aws-profile <profile>        AWS profile to use (default: "default")
  --aws-spot-instance            Enable spot instances for cost savings

Azure-Specific Flags:
  --azure-region <region>        Azure region (default: "eastus")
  --azure-subscription <id>      Azure subscription ID
  --azure-spot-instance          Enable spot instances

GCP-Specific Flags:
  --gcp-region <region>          GCP region (default: "us-central1")
  --gcp-zone <zone>              GCP zone (default: "<region>-a")
  --gcp-project <project>        GCP project ID
  --gcp-spot-instance            Enable spot (preemptible) instances

Hetzner-Specific Flags:
  --hetzner-location <loc>       Hetzner location (default: "nbg1")
  --hetzner-network-zone <zone>  Hetzner network zone (default: "eu-central")
  --hetzner-token <token>        Hetzner API token

DigitalOcean-Specific Flags:
  --digitalocean-region <region> DigitalOcean region (default: "nyc3")
  --digitalocean-token <token>   DigitalOcean API token

Libvirt-Specific Flags:
  --libvirt-memory <gb>          Memory per VM in GB (default: 4)
  --libvirt-vcpus <n>            vCPUs per VM (default: 2)
  --libvirt-network <name>       Network name (default: "default")
  --libvirt-pool <name>          Storage pool name (default: "default")

Examples:
  # List available providers
  exasol init --list-providers

  # List available versions
  exasol init --list-versions

  # Initialize AWS deployment with default version
  exasol init --cloud-provider aws --deployment-dir ./my-deployment

  # Initialize AWS with specific version, 4-node cluster, and spot instances
  exasol init --cloud-provider aws --db-version 8.0.0-x86_64 --cluster-size 4 --aws-spot-instance

  # Initialize Azure deployment
  exasol init --cloud-provider azure --azure-region westus2 --azure-subscription <sub-id>

  # Initialize GCP deployment with spot instances
  exasol init --cloud-provider gcp --gcp-project my-project --gcp-spot-instance

  # Initialize libvirt deployment for local testing
  exasol init --cloud-provider libvirt --libvirt-memory 8 --libvirt-vcpus 4
EOF
}

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
    local owner="exasol-deployer"
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
    local gcp_zone=""
    local gcp_project=""
    local gcp_spot_instance=false

    # Hetzner-specific variables
    local hetzner_location="nbg1"
    local hetzner_network_zone="eu-central"
    local hetzner_token=""

    # DigitalOcean-specific variables
    local digitalocean_region="nyc3"
    local digitalocean_token=""

    # Libvirt-specific variables
    local libvirt_memory_gb=4
    local libvirt_vcpus=2
    local libvirt_network_bridge="default"
    local libvirt_disk_pool="default"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_init_help
                return 0
                ;;
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
            --gcp-zone)
                gcp_zone="$2"
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
            --hetzner-network-zone)
                hetzner_network_zone="$2"
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
            # Libvirt-specific options
            --libvirt-memory)
                libvirt_memory_gb="$2"
                shift 2
                ;;
            --libvirt-vcpus)
                libvirt_vcpus="$2"
                shift 2
                ;;
            --libvirt-network)
                libvirt_network_bridge="$2"
                shift 2
                ;;
            --libvirt-pool)
                libvirt_disk_pool="$2"
                shift 2
                ;;
            --list-versions)
                log_info "Available database versions:"
                list_versions
                return 0
                ;;
            --list-providers)
                log_info "Supported cloud providers (stop/start capabilities):"
                log_info "  provider       | services       | infra power"
                log_info "  ------------------------------------------------------"
                local ordered_providers=(aws azure gcp hetzner digitalocean)
                for provider in "${ordered_providers[@]}"; do
                    local name="${SUPPORTED_PROVIDERS[$provider]}"
                    local services_box="[✓] services"
                    local infra_box=""
                    case "$provider" in
                        aws|azure|gcp)
                            infra_box="[✓] tofu power control"
                            ;;
                        hetzner|digitalocean)
                            infra_box="[ ] manual power-on (in-guest shutdown)"
                            ;;
                        *)
                            infra_box="[ ] manual"
                            ;;
                    esac
                    log_info "  $(printf '%-13s | %-14s | %s' "$provider" "$services_box" "$infra_box")"
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

    # Check provider-specific requirements
    check_provider_requirements "$cloud_provider"

    # Set defaults
    if [[ -z "$deploy_dir" ]]; then
        deploy_dir="$(pwd)"
    fi
    deploy_dir=$(validate_directory "$deploy_dir")

    # Set deployment directory for progress tracking
    export EXASOL_DEPLOY_DIR="$deploy_dir"

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

    if [[ "$cloud_provider" == "digitalocean" && "$architecture" == "arm64" ]]; then
        die "DigitalOcean deployments currently support only x86_64 database versions. Please select an x86_64 build instead of $db_version."
    fi

    # Set default instance type if not provided
    if [[ -z "$instance_type" ]]; then
        if [[ "$cloud_provider" == "libvirt" ]]; then
            instance_type=$(get_version_config "$db_version" "DEFAULT_INSTANCE_TYPE_LIBVIRT" || echo "libvirt-custom")
            log_info "Using default instance type for libvirt: $instance_type"
        else
            instance_type=$(get_version_config "$db_version" "DEFAULT_INSTANCE_TYPE")
            log_info "Using default instance type for $cloud_provider: $instance_type"
        fi
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
            log_info "  Hetzner Network Zone: $hetzner_network_zone"
            ;;
        digitalocean)
            log_info "  DigitalOcean Region: $digitalocean_region"
            ;;
        libvirt)
            log_info "  Libvirt Memory: ${libvirt_memory_gb}GB"
            log_info "  Libvirt vCPUs: $libvirt_vcpus"
            log_info "  Libvirt Network: $libvirt_network_bridge"
            log_info "  Libvirt Storage Pool: $libvirt_disk_pool"
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
    # Note: common-variables.tf is documentation only, not copied
    if [[ -d "$script_root/templates/terraform-common" ]]; then
        cp "$script_root/templates/terraform-common/common.tf" "$templates_dir/" 2>/dev/null || true
        cp "$script_root/templates/terraform-common/common-firewall.tf" "$templates_dir/" 2>/dev/null || true
        cp "$script_root/templates/terraform-common/common-outputs.tf" "$templates_dir/" 2>/dev/null || true
        cp "$script_root/templates/terraform-common/inventory.tftpl" "$templates_dir/" 2>/dev/null || true
        log_debug "Copied common Terraform resources (common.tf, common-firewall.tf, common-outputs.tf, inventory.tftpl)"
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
    if [[ "$cloud_provider" == "gcp" && -z "$gcp_zone" ]]; then
        gcp_zone="${gcp_region}-a"
        log_info "Using default GCP zone: $gcp_zone"
    fi

    log_info "Creating variables file..."
    write_provider_variables "$deploy_dir" "$cloud_provider" \
        "$aws_region" "$aws_profile" "$aws_spot_instance" \
        "$azure_region" "$azure_subscription" "$azure_spot_instance" \
        "$gcp_region" "$gcp_zone" "$gcp_project" "$gcp_spot_instance" \
        "$hetzner_location" "$hetzner_network_zone" "$hetzner_token" \
        "$digitalocean_region" "$digitalocean_token" \
        "$libvirt_memory_gb" "$libvirt_vcpus" "$libvirt_network_bridge" "$libvirt_disk_pool" \
        "$instance_type" "$architecture" "$cluster_size" \
        "$data_volume_size" "$data_volumes_per_node" "$root_volume_size" \
        "$allowed_cidr" "$owner"

    # Store passwords and deployment metadata securely
    local credentials_file="$deploy_dir/.credentials.json"

    # Get download URLs and checksums from version config
    local db_url c4_url db_working_copy db_checksum c4_checksum
    local raw_db_checksum raw_c4_checksum
    db_url=$(get_version_config "$db_version" "DB_DOWNLOAD_URL")
    c4_url=$(get_version_config "$db_version" "C4_DOWNLOAD_URL")
    db_working_copy=$(get_version_config "$db_version" "DB_VERSION")
    raw_db_checksum=$(get_version_config "$db_version" "DB_CHECKSUM")
    raw_c4_checksum=$(get_version_config "$db_version" "C4_CHECKSUM")
    db_checksum=$(normalize_checksum_value "$raw_db_checksum")
    c4_checksum=$(normalize_checksum_value "$raw_c4_checksum")

    # Expand ~/ and $HOME in file:// URLs
    db_url=$(echo "$db_url" | sed "s|^file://~/|file://$HOME/|" | sed "s|\$HOME|$HOME|g")
    c4_url=$(echo "$c4_url" | sed "s|^file://~/|file://$HOME/|" | sed "s|\$HOME|$HOME|g")

    cat > "$credentials_file" <<EOF
{
  "db_password": "$db_password",
  "adminui_password": "$adminui_password",
  "db_download_url": "$db_url",
  "c4_download_url": "$c4_url",
  "db_working_copy": "$db_working_copy",
  "db_checksum": "$db_checksum",
  "c4_checksum": "$c4_checksum",
  "cloud_provider": "$cloud_provider",
  "created_at": "$(get_timestamp)"
}
EOF
    chmod 600 "$credentials_file"

    # Create README
    create_readme "$deploy_dir" "$cloud_provider" "$db_version" "$architecture" \
        "$cluster_size" "$instance_type" "$aws_region" "$azure_region" "$gcp_region" \
        "$libvirt_memory_gb" "$libvirt_vcpus" "$libvirt_network_bridge" "$libvirt_disk_pool"

    # Generate INFO.txt file
    generate_info_files "$deploy_dir"

    log_info ""
    log_info "✅ Deployment directory initialized successfully!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review configuration in: $deploy_dir/variables.auto.tfvars"
    log_info "  2. Deploy with: exasol deploy --deployment-dir $deploy_dir"
    log_info ""
    log_info "Credentials saved to: $deploy_dir/.credentials.json"
    log_info "Deployment info: $deploy_dir/INFO.txt"
}

# Calculate the best availability zone for AWS based on instance type availability
calculate_aws_availability_zone() {
    local aws_region="$1"
    local aws_profile="$2"
    local instance_type="$3"

    log_debug "Calculating best availability zone for instance type $instance_type in region $aws_region"

    # Create a temporary directory for the AZ query
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' RETURN

    # Create a minimal Terraform configuration to query available AZs
    cat > "$temp_dir/az_query.tf" <<EOF
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "$aws_region"
  profile = "$aws_profile"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ec2_instance_type_offerings" "supported" {
  filter {
    name   = "instance-type"
    values = ["$instance_type"]
  }

  filter {
    name   = "location"
    values = data.aws_availability_zones.available.names
  }

  location_type = "availability-zone"
}

output "supported_azs" {
  value = tolist(data.aws_ec2_instance_type_offerings.supported.locations)
}
EOF

    # Initialize and query using tofu
    cd "$temp_dir" || die "Failed to change to temp directory"

    if ! tofu init -upgrade >/dev/null 2>&1; then
        log_error "Failed to initialize tofu for AZ query"
        die "Failed to query availability zones using tofu"
    fi

    # Get the list of supported AZs
    local supported_azs
    supported_azs=$(tofu apply -auto-approve -refresh-only >/dev/null 2>&1 && tofu output -json supported_azs 2>/dev/null | jq -r '.[]' 2>/dev/null)

    if [[ -z "$supported_azs" ]]; then
        log_error "Failed to query availability zones or instance type $instance_type is not available in region $aws_region"
        die "Instance type $instance_type is not available in region $aws_region. Please choose a different instance type or region."
    fi

    # Select the first available AZ
    local selected_az
    selected_az=$(echo "$supported_azs" | head -n1)

    if [[ -z "$selected_az" ]]; then
        log_error "No availability zones found for instance type $instance_type in region $aws_region"
        die "Instance type $instance_type is not available in any AZ within region $aws_region. Please choose a different instance type or region."
    fi

    log_info "Selected availability zone: $selected_az"
    echo "$selected_az"
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
    local gcp_zone="${10}"
    local gcp_project="${11}"
    local gcp_spot_instance="${12}"
    local hetzner_location="${13}"
    local hetzner_network_zone="${14}"
    local hetzner_token="${15}"
    local digitalocean_region="${16}"
    local digitalocean_token="${17}"
    local libvirt_memory_gb="${18}"
    local libvirt_vcpus="${19}"
    local libvirt_network_bridge="${20}"
    local libvirt_disk_pool="${21}"
    local instance_type="${22}"
    local architecture="${23}"
    local cluster_size="${24}"
    local data_volume_size="${25}"
    local data_volumes_per_node="${26}"
    local root_volume_size="${27}"
    local allowed_cidr="${28}"
    local owner="${29}"

    case "$cloud_provider" in
        aws)
            # Calculate the best availability zone for the instance type
            local aws_availability_zone
            aws_availability_zone=$(calculate_aws_availability_zone "$aws_region" "$aws_profile" "$instance_type")

            write_variables_file "$deploy_dir" \
                "aws_region=$aws_region" \
                "aws_profile=$aws_profile" \
                "availability_zone=$aws_availability_zone" \
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
                "gcp_zone=$gcp_zone" \
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
                "hetzner_network_zone=$hetzner_network_zone" \
                "hetzner_token=$hetzner_token" \
                "instance_type=$instance_type" \
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
                "instance_type=$instance_type" \
                "instance_architecture=$architecture" \
                "node_count=$cluster_size" \
                "data_volume_size=$data_volume_size" \
                "data_volumes_per_node=$data_volumes_per_node" \
                "root_volume_size=$root_volume_size" \
                "allowed_cidr=$allowed_cidr" \
                "owner=$owner"
            ;;
        libvirt)
            write_variables_file "$deploy_dir" \
                "libvirt_memory_gb=$libvirt_memory_gb" \
                "libvirt_vcpus=$libvirt_vcpus" \
                "libvirt_network_bridge=$libvirt_network_bridge" \
                "libvirt_disk_pool=$libvirt_disk_pool" \
                "instance_type=$instance_type" \
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
    local libvirt_memory_gb="${10}"
    local libvirt_vcpus="${11}"
    local libvirt_network_bridge="${12}"
    local libvirt_disk_pool="${13}"

    local region_info=""
    local additional_config=""
    case "$cloud_provider" in
        aws) 
            region_info="AWS Region: $aws_region"
            ;;
        azure) 
            region_info="Azure Region: $azure_region"
            ;;
        gcp) 
            region_info="GCP Region: $gcp_region"
            ;;
        libvirt) 
            region_info="Local KVM Deployment"
            additional_config="- **Memory**: ${libvirt_memory_gb}GB per VM\n- **vCPUs**: $libvirt_vcpus per VM\n- **Network**: $libvirt_network_bridge\n- **Storage Pool**: $libvirt_disk_pool"
            ;;
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
$([ -n "$additional_config" ] && echo -e "$additional_config")

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

    ln -sf ".templates/common.tf" "$deploy_dir/common.tf"
    ln -sf ".templates/common-firewall.tf" "$deploy_dir/common-firewall.tf"
    ln -sf ".templates/common-outputs.tf" "$deploy_dir/common-outputs.tf"
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
