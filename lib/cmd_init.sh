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

# Supported cloud providers (keep Bash 3 compatible)
SUPPORTED_PROVIDERS=("aws" "azure" "gcp" "hetzner" "digitalocean" "libvirt")

get_supported_providers_list() {
    echo "${SUPPORTED_PROVIDERS[*]}"
}

get_provider_description() {
    local provider="$1"
    case "$provider" in
        aws) echo "Amazon Web Services" ;;
        azure) echo "Microsoft Azure" ;;
        gcp) echo "Google Cloud Platform" ;;
        hetzner) echo "Hetzner Cloud" ;;
        digitalocean) echo "DigitalOcean" ;;
        libvirt) echo "Local libvirt/KVM deployment" ;;
        *) echo "$provider" ;;
    esac
}

provider_supported() {
    local provider="$1"
    for p in "${SUPPORTED_PROVIDERS[@]}"; do
        if [[ "$p" == "$provider" ]]; then
            return 0
        fi
    done
    return 1
}

# Normalize checksum values (strip algorithm prefix like "sha256:")
normalize_checksum_value() {
    local value="${1:-}"

    if [[ -z "$value" ]]; then
        echo ""
        return
    fi

    local normalized="${value#*:}"
    local lowered
    lowered=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
    if [[ "$lowered" == sha256:* ]]; then
        echo "$normalized"
    else
        echo "$value"
    fi
}

# Resolve API token from explicit flag, environment variable, or fallback file
# Usage: resolve_provider_token "<current_value>" "<ENV_VAR_NAME>" "<file_path>" "<Provider Name>"
resolve_provider_token() {
    local current_value="${1:-}"
    local env_var_name="${2:-}"
    local file_path="${3:-}"
    local provider_name="${4:-Token}"

    if [[ -n "$current_value" ]]; then
        echo "$current_value"
        return 0
    fi

    # shellcheck disable=SC2016
    local env_value="${!env_var_name:-}"
    if [[ -n "$env_value" ]]; then
        log_info "Using $provider_name token from \$$env_var_name"
        echo "$env_value"
        return 0
    fi

    if [[ -n "$file_path" && -f "$file_path" ]]; then
        local file_value
        file_value=$(<"$file_path")
        file_value="${file_value//$'\r'/}"
        file_value="${file_value//$'\n'/}"
        if [[ -n "$file_value" ]]; then
            log_info "Using $provider_name token from $file_path"
            echo "$file_value"
            return 0
        fi
    fi

    echo ""
}

# Load Azure credentials from a JSON file (output of az ad sp create-for-rbac)
load_azure_credentials_file() {
    local file_path="${1:-}"

    # Expand leading ~ to HOME for consistency
    if [[ $file_path == ~/* ]]; then
        file_path="${HOME}${file_path#~}"
    fi

    if [[ -z "$file_path" || ! -f "$file_path" ]]; then
        echo ""
        return 1
    fi

    local client_id client_secret tenant_id subscription_id
    client_id=$(jq -r '.appId // .clientId // empty' "$file_path" 2>/dev/null || true)
    client_secret=$(jq -r '.password // .clientSecret // empty' "$file_path" 2>/dev/null || true)
    tenant_id=$(jq -r '.tenant // .tenantId // empty' "$file_path" 2>/dev/null || true)
    subscription_id=$(jq -r '.subscriptionId // empty' "$file_path" 2>/dev/null || true)

    if [[ -z "$client_id" || -z "$client_secret" || -z "$tenant_id" ]]; then
        log_warn "Azure credentials file $file_path is missing appId/password/tenant fields"
        echo ""
        return 1
    fi

    echo "$file_path|$client_id|$client_secret|$tenant_id|$subscription_id"
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
  --azure-subscription <id>      Azure subscription ID (optional if set in env or credentials file)
  --azure-credentials-file <path>  Path to Azure service principal credentials JSON (default: "~/.azure_credentials")
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
  --libvirt-uri <uri>            Libvirt connection URI (auto-detected if not provided)

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
    local aws_region=""
    local aws_profile="default"
    local aws_spot_instance=false

    # Azure-specific variables
    local azure_region=""
    local azure_subscription=""
    local azure_credentials_file="$HOME/.azure_credentials"
    local azure_client_id=""
    local azure_client_secret=""
    local azure_tenant_id=""
    local azure_spot_instance=false

    # GCP-specific variables
    local gcp_region=""
    local gcp_zone=""
    local gcp_project=""
    local gcp_spot_instance=false

    # Hetzner-specific variables
    local hetzner_location=""
    local hetzner_network_zone="eu-central"
    local hetzner_token=""

    # DigitalOcean-specific variables
    local digitalocean_region=""
    local digitalocean_token=""

    # Libvirt-specific variables
    local libvirt_memory_gb=4
    local libvirt_vcpus=2
    local libvirt_network_bridge="default"
    local libvirt_disk_pool="default"
    local libvirt_uri=""

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
            --azure-credentials-file)
                azure_credentials_file="$2"
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
            --libvirt-uri)
                libvirt_uri="$2"
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
        log_info "Supported providers: $(get_supported_providers_list)"
        log_info "Use --list-providers to see all supported providers"
        return 1
    fi

    if ! provider_supported "$cloud_provider"; then
        log_error "Unsupported cloud provider: $cloud_provider"
        log_info "Supported providers: $(get_supported_providers_list)"
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
    log_plugin_cache_dir

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

    # Override for macOS arm64 hosts using libvirt
    if [[ "$(uname -m)" == "arm64" && "$cloud_provider" == "libvirt" ]]; then
        architecture="arm64"
        log_info "Detected arm64 host architecture, using arm64 for libvirt VMs"
    fi

    if [[ "$cloud_provider" == "digitalocean" && "$architecture" == "arm64" ]]; then
        die "DigitalOcean deployments currently support only x86_64 database versions. Please select an x86_64 build instead of $db_version."
    fi

    # Resolve provider tokens from environment or default files when not passed explicitly
    if [[ "$cloud_provider" == "hetzner" ]]; then
        hetzner_token=$(resolve_provider_token "$hetzner_token" "HETZNER_TOKEN" "$HOME/.hetzner_token" "Hetzner")
    fi

    if [[ "$cloud_provider" == "digitalocean" ]]; then
        digitalocean_token=$(resolve_provider_token "$digitalocean_token" "DIGITALOCEAN_TOKEN" "$HOME/.digitalocean_token" "DigitalOcean")
    fi

    # Resolve Azure credentials from file for service principal authentication
    if [[ "$cloud_provider" == "azure" ]]; then
        local azure_credentials_data
        azure_credentials_data=$(load_azure_credentials_file "$azure_credentials_file") || true
        
        local file_subscription_id=""
        if [[ -n "$azure_credentials_data" ]]; then
            IFS="|" read -r azure_credentials_file azure_client_id azure_client_secret azure_tenant_id file_subscription_id <<<"$azure_credentials_data"
            log_info "Using Azure credentials file: $azure_credentials_file"
        else
            log_warn "Azure credentials file not found or incomplete at $azure_credentials_file. Create it with 'az ad sp create-for-rbac --name \"exasol-deployer\" --role contributor --scopes /subscriptions/<subscription-id> > ~/.azure_credentials'."
        fi

        # Precedence: 1. Flag (already in azure_subscription), 2. Env Var, 3. Config File
        if [[ -z "$azure_subscription" ]]; then
            if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
                azure_subscription="${AZURE_SUBSCRIPTION_ID}"
                log_info "Using Azure subscription ID from AZURE_SUBSCRIPTION_ID environment variable"
            elif [[ -n "$file_subscription_id" ]]; then
                azure_subscription="$file_subscription_id"
                log_info "Using Azure subscription ID from credentials file"
            fi
        fi

        if [[ -z "$azure_subscription" ]]; then
            die "Azure subscription ID is required. Please provide it via --azure-subscription, AZURE_SUBSCRIPTION_ID env var, or 'subscriptionId' in ~/.azure_credentials"
        fi

        if [[ -z "$azure_client_id" || -z "$azure_client_secret" || -z "$azure_tenant_id" ]]; then
            die "Azure credentials are incomplete. Please ensure '$azure_credentials_file' exists and contains 'appId', 'password', and 'tenant'."
        fi
    fi


    # Set default instance type if not provided
    if [[ -z "$instance_type" ]]; then
        if [[ "$cloud_provider" == "libvirt" ]]; then
            instance_type=$(get_version_config "$db_version" "DEFAULT_INSTANCE_TYPE_LIBVIRT" || echo "libvirt-custom")
            log_info "Using default instance type for libvirt: $instance_type"
        else
            instance_type=$(get_instance_type_default "$cloud_provider" "$architecture")
            if [[ -z "$instance_type" ]]; then
                die "No default instance type found for provider '$cloud_provider' and architecture '$architecture'"
            fi
            log_info "Using default instance type for $cloud_provider ($architecture): $instance_type"
        fi
    fi

    # Set default region/location if not provided, using instance-types.conf
    if [[ "$cloud_provider" == "aws" && -z "$aws_region" ]]; then
        aws_region=$(get_instance_type_region_default "$cloud_provider")
        log_info "Using default AWS region: $aws_region"
    fi
    if [[ "$cloud_provider" == "azure" && -z "$azure_region" ]]; then
        azure_region=$(get_instance_type_region_default "$cloud_provider")
        log_info "Using default Azure region: $azure_region"
    fi
    if [[ "$cloud_provider" == "gcp" && -z "$gcp_region" ]]; then
        gcp_region=$(get_instance_type_region_default "$cloud_provider")
        log_info "Using default GCP region: $gcp_region"
    fi
    if [[ "$cloud_provider" == "hetzner" && -z "$hetzner_location" ]]; then
        hetzner_location=$(get_instance_type_region_default "$cloud_provider" location)
        log_info "Using default Hetzner location: $hetzner_location"
    fi
    if [[ "$cloud_provider" == "hetzner" && -z "$hetzner_network_zone" ]]; then
        hetzner_network_zone=$(get_instance_type_region_default "$cloud_provider" network_zone)
        log_info "Using default Hetzner network zone: $hetzner_network_zone"
    fi
    if [[ "$cloud_provider" == "digitalocean" && -z "$digitalocean_region" ]]; then
        digitalocean_region=$(get_instance_type_region_default "$cloud_provider")
        log_info "Using default DigitalOcean region: $digitalocean_region"
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
    log_info "  Cloud Provider: $(get_provider_description "$cloud_provider")"
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
            if [[ -n "$azure_client_id" ]]; then
                log_info "  Azure Credentials File: $azure_credentials_file"
            fi
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
            if [[ "$root_volume_size" -ne 50 ]]; then
                log_warn "  Note: --root-volume-size is ignored for DigitalOcean. Disk size is determined by the instance type (e.g., s-2vcpu-4gb = 80GB)"
            fi
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

    # Write variables file based on cloud provider
    if [[ "$cloud_provider" == "gcp" && -z "$gcp_zone" ]]; then
        gcp_zone="${gcp_region}-a"
        log_info "Using default GCP zone: $gcp_zone"
    fi

    if [[ "$cloud_provider" == "libvirt" ]]; then
        libvirt_uri=$(detect_libvirt_uri "$libvirt_uri")
        if [[ -z "$libvirt_uri" ]]; then
            die "Failed to determine libvirt URI automatically. Please rerun with --libvirt-uri <uri>."
        fi
    fi

    # Validate DigitalOcean token
    if [[ "$cloud_provider" == "digitalocean" ]]; then
        if [[ "${EXASOL_SKIP_PROVIDER_CHECKS:-}" == "1" ]]; then
            log_warn "Skipping DigitalOcean token validation because EXASOL_SKIP_PROVIDER_CHECKS=1"
        else
            # If token is empty, try to read from ~/.digitalocean_token
            if [[ -z "$digitalocean_token" ]]; then
                local token_file="$HOME/.digitalocean_token"
                if [[ -f "$token_file" ]]; then
                    digitalocean_token=$(tr -d '[:space:]' < "$token_file")
                    log_info "Using DigitalOcean token from $token_file"
                else
                    die "DigitalOcean token is required. Please provide via --digitalocean-token or create ~/.digitalocean_token file"
                fi
            fi

            # Validate token is not empty after reading from file
            if [[ -z "$digitalocean_token" ]]; then
                die "DigitalOcean token cannot be empty"
            fi
        fi
    fi

    log_info "Creating variables file..."
    write_provider_variables "$deploy_dir" "$cloud_provider" \
        "$aws_region" "$aws_profile" "$aws_spot_instance" \
        "$azure_region" "$azure_subscription" "$azure_client_id" "$azure_client_secret" "$azure_tenant_id" "$azure_spot_instance" \
        "$gcp_region" "$gcp_zone" "$gcp_project" "$gcp_spot_instance" \
        "$hetzner_location" "$hetzner_network_zone" "$hetzner_token" \
        "$digitalocean_region" "$digitalocean_token" \
        "$libvirt_memory_gb" "$libvirt_vcpus" "$libvirt_network_bridge" "$libvirt_disk_pool" "$libvirt_uri" \
        "$instance_type" "$architecture" "$cluster_size" \
        "$data_volume_size" "$data_volumes_per_node" "$root_volume_size" \
        "$allowed_cidr" "$owner"

    # Create Terraform files in deployment directory (after variables are written so macOS HVF can be detected)
    create_terraform_files "$deploy_dir" "$architecture" "$cloud_provider"

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

    if [[ "${EXASOL_SKIP_PROVIDER_CHECKS:-}" == "1" ]]; then
        echo "${aws_region}a"
        return 0
    fi

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
        local fallback="${aws_region}a"
        log_warn "Failed to initialize tofu for AZ query, using fallback AZ: $fallback"
        echo "$fallback"
        return 0
    fi

    # Get the list of supported AZs
    local supported_azs
    supported_azs=$(tofu apply -auto-approve -refresh-only >/dev/null 2>&1 && tofu output -json supported_azs 2>/dev/null | jq -r '.[]' 2>/dev/null)

    if [[ -z "$supported_azs" ]]; then
        # Fallback: Use region + 'a' when AWS APIs are unavailable (e.g., CI environments)
        local selected_az="${aws_region}a"
        log_warn "Could not query AWS for availability zones, using fallback: $selected_az"
        log_info "Selected availability zone: $selected_az"
        echo "$selected_az"
    else
        # Select the first available AZ from AWS API results
        local selected_az
        selected_az=$(echo "$supported_azs" | head -n1)

        if [[ -z "$selected_az" ]]; then
            log_error "No availability zones found for instance type $instance_type in region $aws_region"
            die "Instance type $instance_type is not available in any AZ within region $aws_region. Please choose a different instance type or region."
        fi

        log_info "Selected availability zone: $selected_az"
        echo "$selected_az"
    fi
}

# Detect libvirt URI via CLI flag or virsh
detect_libvirt_uri() {
    local override="${1:-}"

    if [[ -n "$override" ]]; then
        log_info "Using libvirt URI from --libvirt-uri"
        echo "$override"
        return 0
    fi

    if [[ "${EXASOL_SKIP_PROVIDER_CHECKS:-}" == "1" ]]; then
        log_warn "EXASOL_SKIP_PROVIDER_CHECKS=1 set; defaulting libvirt URI to qemu:///system without validation."
        echo "qemu:///system"
        return 0
    fi

    local virsh_uri=""
    if command -v virsh >/dev/null 2>&1; then
        virsh_uri="$(virsh uri 2>/dev/null | tr -d '\r\n' || true)"
    fi

    if [[ -n "$virsh_uri" ]]; then
        if [[ "$virsh_uri" == *session* ]]; then
            log_error "Detected libvirt URI is a session daemon ($virsh_uri). Only system libvirt is supported."
            return 1
        fi
        log_info "Detected libvirt URI via 'virsh uri': $virsh_uri"
        echo "$virsh_uri"
        return 0
    fi

    log_error "Unable to detect libvirt URI automatically via 'virsh uri'. Install libvirt-clients/daemon and rerun with --libvirt-uri qemu:///system or qemu+ssh://user@host/system."
    return 1
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
    local azure_client_id="$8"
    local azure_client_secret="$9"
    local azure_tenant_id="${10}"
    local azure_spot_instance="${11}"
    local gcp_region="${12}"
    local gcp_zone="${13}"
    local gcp_project="${14}"
    local gcp_spot_instance="${15}"
    local hetzner_location="${16}"
    local hetzner_network_zone="${17}"
    local hetzner_token="${18}"
    local digitalocean_region="${19}"
    local digitalocean_token="${20}"
    local libvirt_memory_gb="${21}"
    local libvirt_vcpus="${22}"
    local libvirt_network_bridge="${23}"
    local libvirt_disk_pool="${24}"
    local libvirt_uri="${25}"
    local instance_type="${26}"
    local architecture="${27}"
    local cluster_size="${28}"
    local data_volume_size="${29}"
    local data_volumes_per_node="${30}"
    local root_volume_size="${31}"
    local allowed_cidr="${32}"
    local owner="${33}"

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
            local azure_vars=(
                "azure_region=$azure_region"
                "azure_subscription=$azure_subscription"
                "instance_type=$instance_type"
                "instance_architecture=$architecture"
                "node_count=$cluster_size"
                "data_volume_size=$data_volume_size"
                "data_volumes_per_node=$data_volumes_per_node"
                "root_volume_size=$root_volume_size"
                "allowed_cidr=$allowed_cidr"
                "owner=$owner"
                "enable_spot_instances=$azure_spot_instance"
            )
            if [[ -n "$azure_client_id" ]]; then
                azure_vars+=("azure_client_id=$azure_client_id")
            fi
            if [[ -n "$azure_client_secret" ]]; then
                azure_vars+=("azure_client_secret=$azure_client_secret")
            fi
            if [[ -n "$azure_tenant_id" ]]; then
                azure_vars+=("azure_tenant_id=$azure_tenant_id")
            fi

            write_variables_file "$deploy_dir" "${azure_vars[@]}"
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
            local libvirt_domain_type="kvm"
            local libvirt_firmware="efi"
            write_variables_file "$deploy_dir" \
                "libvirt_memory_gb=$libvirt_memory_gb" \
                "libvirt_vcpus=$libvirt_vcpus" \
                "libvirt_network_bridge=$libvirt_network_bridge" \
                "libvirt_disk_pool=$libvirt_disk_pool" \
                "libvirt_uri=$libvirt_uri" \
                "libvirt_domain_type=$libvirt_domain_type" \
                "libvirt_firmware=$libvirt_firmware" \
                "instance_type=$instance_type" \
                "instance_architecture=$architecture" \
                "node_count=$cluster_size" \
                "data_volume_size=$data_volume_size" \
                "data_volumes_per_node=$data_volumes_per_node" \
                "root_volume_size=$root_volume_size" \
                "allowed_cidr=$allowed_cidr" \
                "owner=$owner"

            # Check and create default libvirt storage pool if it doesn't exist
            if ! virsh -c "$libvirt_uri" version >/dev/null 2>&1; then
                log_warn "Cannot connect to libvirt URI $libvirt_uri, ensure libvirt daemon is running. Skipping pool creation."
            elif ! virsh -c "$libvirt_uri" pool-list --name 2>/dev/null | grep -q "^default$"; then
                log_info "Default libvirt storage pool not found, attempting to create it"
                pool_path="/var/lib/libvirt/images"
                mkdir -p "$pool_path" || log_warn "Could not create pool directory $pool_path, you may need to adjust permissions"
                if virsh -c "$libvirt_uri" pool-define-as default dir --target "$pool_path" 2>/dev/null; then
                    log_info "Default pool defined successfully"
                    if virsh -c "$libvirt_uri" pool-start default 2>/dev/null; then
                        log_info "Default pool started successfully"
                    else
                        log_warn "Could not start default pool"
                    fi
                    if ! virsh -c "$libvirt_uri" pool-autostart default 2>/dev/null; then
                        log_warn "Could not set default pool to autostart"
                    fi
                else
                    log_warn "Could not define default pool, ensure libvirt is running and you have permissions"
                fi
            fi

            # Check and create default libvirt network if it doesn't exist
            if ! virsh -c "$libvirt_uri" net-list --name 2>/dev/null | grep -q "^default$"; then
                log_info "Default libvirt network not found, attempting to create it"
                if virsh -c "$libvirt_uri" net-define /dev/stdin 2>/dev/null <<EOF; then
<network>
  <name>default</name>
  <forward mode="nat"/>
  <ip address="10.0.0.1" netmask="255.255.255.0">
    <dhcp>
      <range start="10.0.0.2" end="10.0.0.254"/>
    </dhcp>
  </ip>
</network>
EOF
                    log_info "Default network defined successfully"
                    if virsh -c "$libvirt_uri" net-start default 2>/dev/null; then
                        log_info "Default network started successfully"
                    else
                        log_warn "Could not start default network. For session mode, you may need to start it manually with appropriate permissions."
                    fi
                    if ! virsh -c "$libvirt_uri" net-autostart default 2>/dev/null; then
                        log_warn "Could not set default network to autostart"
                    fi
                else
                    log_warn "Could not define default network, ensure libvirt is running and you have permissions"
                fi
            fi
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

- **Cloud Provider**: $(get_provider_description "$cloud_provider")
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
        # No provider-specific cloud-init templates are symlinked by default.

    # Inventory template may be cloud-specific
    if [[ -f "$templates_dir/inventory-$cloud_provider.tftpl" ]]; then
        ln -sf ".templates/inventory-$cloud_provider.tftpl" "$deploy_dir/inventory.tftpl"
    else
        ln -sf ".templates/inventory.tftpl" "$deploy_dir/inventory.tftpl"
    fi

    log_debug "Created Terraform configuration files for $cloud_provider"
}
