#!/usr/bin/env bash
# Unified cloud resource cleanup script for Exasol Deployer
# Supports: AWS, Azure, GCP, Hetzner, DigitalOcean, Libvirt

set -euo pipefail

# Colors for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RESET='\033[0m'

# Logging functions
log_info() {
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*" >&2
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

die() {
    log_error "$*"
    exit 1
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 --provider <PROVIDER> [OPTIONS]

Cleanup cloud resources for Exasol Deployer.

Required:
  --provider <PROVIDER>    Cloud provider: aws, azure, gcp, hetzner, digitalocean, libvirt

Optional:
  --tag <TAG>             Filter resources by tag/label (e.g., owner=team-name)
  --prefix <PREFIX>       Filter resources by name prefix (default: exasol)
  --dry-run               Show what would be deleted without deleting
  --yes                   Skip confirmation prompt
  --help                  Show this help message

Examples:
  # List all Azure resources
  $0 --provider azure --dry-run

  # Delete all Hetzner resources with confirmation
  $0 --provider hetzner


  # Delete AWS resources with tag filter
  $0 --provider aws --tag owner=dev-team --yes

  # Delete GCP resources without confirmation
  $0 --provider gcp --yes

  # Delete DigitalOcean resources with custom prefix
  $0 --provider digitalocean --prefix myapp

EOF
    exit 0
}

# Parse command line arguments
PROVIDER=""
TAG_FILTER=""  # Reserved for future use
PREFIX_FILTER=""
DRY_RUN=false
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --provider)
            PROVIDER="$2"
            shift 2
            ;;
        --tag)
            # shellcheck disable=SC2034
            TAG_FILTER="$2"  # Reserved for future tag-based filtering
            shift 2
            ;;
        --prefix)
            PREFIX_FILTER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes)
            SKIP_CONFIRM=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            die "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done


# Validate provider
if [[ -z "$PROVIDER" ]]; then
    die "Provider is required. Use --provider <PROVIDER>. See --help for details."
fi

case "$PROVIDER" in
    aws|azure|gcp|hetzner|digitalocean|libvirt)
        ;;
    *)
        die "Unsupported provider: $PROVIDER. Supported: aws, azure, gcp, hetzner, digitalocean, libvirt"
        ;;
esac

# Check required CLI tools
check_cli_tool() {
    local tool="$1"
    local install_hint="$2"
    if ! command -v "$tool" &> /dev/null; then
        die "$tool is not installed. $install_hint"
    fi
}

# Confirmation prompt
confirm_deletion() {
    local resource_count="$1"
    local provider="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would delete $resource_count resource(s) from $provider"
        return 1
    fi
    
    if [[ "$SKIP_CONFIRM" == true ]]; then
        return 0
    fi
    
    echo ""
    local confirmation
    read -r -p "Delete $resource_count resource(s) from $provider? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Deletion cancelled."
        return 1
    fi
    return 0
}


# ============================================================================
# AWS Cleanup
# ============================================================================
cleanup_aws() {
    check_cli_tool "aws" "Install: https://aws.amazon.com/cli/"
    
    log_info "Fetching AWS resources with prefix '$PREFIX_FILTER'..."
    
    # Get default region or use us-east-1
    local region="${AWS_DEFAULT_REGION:-us-east-1}"
    log_info "Using AWS region: $region"
    
    # Find VPCs with exasol prefix
    local vpcs
    vpcs=$(aws ec2 describe-vpcs --region "$region" \
        --filters "Name=tag:Name,Values=${PREFIX_FILTER}*" \
        --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
    
    if [[ -z "$vpcs" ]]; then
        log_info "No AWS VPCs found with prefix '$PREFIX_FILTER'"
        return 0
    fi
    
    echo ""
    echo "=== AWS RESOURCES (Region: $region) ==="
    
    for vpc in $vpcs; do
        echo ""
        echo "VPC: $vpc"
        
        # List instances
        # shellcheck disable=SC2016
        aws ec2 describe-instances --region "$region" \
            --filters "Name=vpc-id,Values=$vpc" \
            --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
            --output table 2>/dev/null || true
        
        # List volumes
        aws ec2 describe-volumes --region "$region" \
            --filters "Name=tag:VpcId,Values=$vpc" \
            --query 'Volumes[].[VolumeId,Size,State]' \
            --output table 2>/dev/null || true
    done
    
    local resource_count
    resource_count=$(echo "$vpcs" | wc -w)
    
    if ! confirm_deletion "$resource_count VPC(s) and associated resources" "AWS"; then
        return 0
    fi
    
    log_info "Deleting AWS resources..."
    for vpc in $vpcs; do
        log_info "Deleting VPC: $vpc"
        
        # Terminate instances
        local instances
        instances=$(aws ec2 describe-instances --region "$region" \
            --filters "Name=vpc-id,Values=$vpc" "Name=instance-state-name,Values=running,stopped" \
            --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")
        
        if [[ -n "$instances" ]]; then
            # shellcheck disable=SC2086
            aws ec2 terminate-instances --region "$region" --instance-ids $instances 2>/dev/null || true
            log_info "  Terminated instances: $instances"
        fi
        
        # Wait for instances to terminate
        if [[ -n "$instances" ]]; then
            log_info "  Waiting for instances to terminate..."
            # shellcheck disable=SC2086
            aws ec2 wait instance-terminated --region "$region" --instance-ids $instances 2>/dev/null || true
        fi
        
        # Delete VPC (this will fail if resources still exist, which is expected)
        aws ec2 delete-vpc --region "$region" --vpc-id "$vpc" 2>/dev/null || \
            log_warn "  Could not delete VPC $vpc (may have dependencies)"
    done
    
    log_info "AWS cleanup initiated (some resources may take time to delete)"
}


# ============================================================================
# Azure Cleanup
# ============================================================================
cleanup_azure() {
    check_cli_tool "az" "Install: https://docs.microsoft.com/cli/azure/install-azure-cli"
    
    log_info "Fetching Azure resources with prefix '$PREFIX_FILTER'..."
    
    # Get all resource groups matching prefix
    local resource_groups
    if [[ -z "$PREFIX_FILTER" ]]; then
        # Empty prefix - get all resource groups except system ones
        resource_groups=$(az group list --query "[?name!='NetworkWatcherRG'].name" -o tsv 2>/dev/null || echo "")
    else
        resource_groups=$(az group list --query "[?starts_with(name, '${PREFIX_FILTER}')].name" -o tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "$resource_groups" ]]; then
        log_info "No Azure resource groups found with prefix '$PREFIX_FILTER'"
        return 0
    fi
    
    echo ""
    echo "=== AZURE RESOURCE GROUPS ==="
    if [[ -z "$PREFIX_FILTER" ]]; then
        az group list --query "[?name!='NetworkWatcherRG']" --output table 2>/dev/null || true
    else
        az group list --query "[?starts_with(name, '${PREFIX_FILTER}')]" --output table 2>/dev/null || true
    fi
    
    echo ""
    echo "=== AZURE RESOURCES ==="
    for rg in $resource_groups; do
        echo ""
        echo "Resource Group: $rg"
        az resource list --resource-group "$rg" --output table 2>/dev/null || true
    done
    
    local resource_count
    resource_count=$(echo "$resource_groups" | wc -l)
    local total_resources
    total_resources=$(az resource list --query "[?starts_with(resourceGroup, '${PREFIX_FILTER}')]" --query "length([])" -o tsv 2>/dev/null || echo "0")
    
    echo ""
    echo "Total: $resource_count resource group(s), $total_resources resource(s)"
    
    if ! confirm_deletion "$resource_count resource group(s)" "Azure"; then
        return 0
    fi
    
    log_info "Deleting Azure resource groups..."
    while IFS= read -r rg; do
        log_info "  Deleting: $rg"
        az group delete --name "$rg" --yes --no-wait 2>/dev/null || \
            log_warn "  Failed to delete resource group: $rg"
    done <<< "$resource_groups"
    
    log_info "Azure cleanup initiated (running in background)"
}


# ============================================================================
# GCP Cleanup
# ============================================================================
cleanup_gcp() {
    check_cli_tool "gcloud" "Install: https://cloud.google.com/sdk/docs/install"
    
    log_info "Fetching GCP resources with prefix '$PREFIX_FILTER'..."
    
    # Get current project
    local project
    project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project" ]]; then
        die "No GCP project configured. Run: gcloud config set project PROJECT_ID"
    fi
    
    log_info "Using GCP project: $project"
    
    # List instances
    local instances
    instances=$(gcloud compute instances list --filter="name~^${PREFIX_FILTER}" \
        --format="table(name,zone,status)" 2>/dev/null || echo "")
    
    # List disks
    local disks
    disks=$(gcloud compute disks list --filter="name~^${PREFIX_FILTER}" \
        --format="table(name,zone,sizeGb,status)" 2>/dev/null || echo "")
    
    # List networks
    local networks
    networks=$(gcloud compute networks list --filter="name~^${PREFIX_FILTER}" \
        --format="table(name,mode)" 2>/dev/null || echo "")
    
    # List firewall rules
    local firewalls
    firewalls=$(gcloud compute firewall-rules list --filter="name~^${PREFIX_FILTER}" \
        --format="table(name,network,direction)" 2>/dev/null || echo "")
    
    echo ""
    echo "=== GCP RESOURCES (Project: $project) ==="
    
    if [[ -n "$instances" ]]; then
        echo ""
        echo "Instances:"
        echo "$instances"
    fi
    
    if [[ -n "$disks" ]]; then
        echo ""
        echo "Disks:"
        echo "$disks"
    fi
    
    if [[ -n "$networks" ]]; then
        echo ""
        echo "Networks:"
        echo "$networks"
    fi
    
    if [[ -n "$firewalls" ]]; then
        echo ""
        echo "Firewall Rules:"
        echo "$firewalls"
    fi
    
    # Count resources
    local instance_count
    instance_count=$(gcloud compute instances list --filter="name~^${PREFIX_FILTER}" --format="value(name)" 2>/dev/null | wc -l)
    local disk_count
    disk_count=$(gcloud compute disks list --filter="name~^${PREFIX_FILTER}" --format="value(name)" 2>/dev/null | wc -l)
    local network_count
    network_count=$(gcloud compute networks list --filter="name~^${PREFIX_FILTER}" --format="value(name)" 2>/dev/null | wc -l)
    
    local total_count=$((instance_count + disk_count + network_count))
    
    if [[ $total_count -eq 0 ]]; then
        log_info "No GCP resources found with prefix '$PREFIX_FILTER'"
        return 0
    fi
    
    echo ""
    echo "Total: $instance_count instance(s), $disk_count disk(s), $network_count network(s)"
    
    if ! confirm_deletion "$total_count" "GCP"; then
        return 0
    fi
    
    log_info "Deleting GCP resources..."
    
    # Delete instances first
    local instance_list
    instance_list=$(gcloud compute instances list --filter="name~^${PREFIX_FILTER}" --format="value(name,zone)" 2>/dev/null || echo "")
    while IFS=$'\t' read -r name zone; do
        if [[ -n "$name" && -n "$zone" ]]; then
            log_info "  Deleting instance: $name (zone: $zone)"
            gcloud compute instances delete "$name" --zone="$zone" --quiet 2>/dev/null || \
                log_warn "  Failed to delete instance: $name"
        fi
    done <<< "$instance_list"
    
    # Delete disks
    local disk_list
    disk_list=$(gcloud compute disks list --filter="name~^${PREFIX_FILTER}" --format="value(name,zone)" 2>/dev/null || echo "")
    while IFS=$'\t' read -r name zone; do
        if [[ -n "$name" && -n "$zone" ]]; then
            log_info "  Deleting disk: $name (zone: $zone)"
            gcloud compute disks delete "$name" --zone="$zone" --quiet 2>/dev/null || \
                log_warn "  Failed to delete disk: $name"
        fi
    done <<< "$disk_list"
    
    # Delete firewall rules
    local firewall_list
    firewall_list=$(gcloud compute firewall-rules list --filter="name~^${PREFIX_FILTER}" --format="value(name)" 2>/dev/null || echo "")
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting firewall rule: $name"
            gcloud compute firewall-rules delete "$name" --quiet 2>/dev/null || \
                log_warn "  Failed to delete firewall rule: $name"
        fi
    done <<< "$firewall_list"
    
    # Delete networks (must be last)
    local network_list
    network_list=$(gcloud compute networks list --filter="name~^${PREFIX_FILTER}" --format="value(name)" 2>/dev/null || echo "")
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting network: $name"
            gcloud compute networks delete "$name" --quiet 2>/dev/null || \
                log_warn "  Failed to delete network: $name"
        fi
    done <<< "$network_list"
    
    log_info "GCP cleanup completed"
}


# ============================================================================
# Hetzner Cleanup
# ============================================================================
cleanup_hetzner() {
    check_cli_tool "hcloud" "Install: https://github.com/hetznercloud/cli"
    
    log_info "Fetching Hetzner resources with prefix '$PREFIX_FILTER'..."
    
    # Check if authenticated
    if ! hcloud server list &>/dev/null; then
        die "Not authenticated with Hetzner. Run: hcloud context create <name>"
    fi
    
    # List servers
    local servers
    servers=$(hcloud server list -o noheader -o columns=name,status,ipv4 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    
    # List volumes
    local volumes
    volumes=$(hcloud volume list -o noheader -o columns=name,size,server 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    
    # List networks
    local networks
    networks=$(hcloud network list -o noheader -o columns=name,ip_range 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    
    # List firewalls
    local firewalls
    firewalls=$(hcloud firewall list -o noheader -o columns=name,rules 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    
    echo ""
    echo "=== HETZNER RESOURCES ==="
    
    if [[ -n "$servers" ]]; then
        echo ""
        echo "Servers:"
        echo "$servers"
    fi
    
    if [[ -n "$volumes" ]]; then
        echo ""
        echo "Volumes:"
        echo "$volumes"
    fi
    
    if [[ -n "$networks" ]]; then
        echo ""
        echo "Networks:"
        echo "$networks"
    fi
    
    if [[ -n "$firewalls" ]]; then
        echo ""
        echo "Firewalls:"
        echo "$firewalls"
    fi
    
    # Count resources
    local server_count=0
    local volume_count=0
    local network_count=0
    local firewall_count=0
    [[ -n "$servers" ]] && server_count=$(echo "$servers" | wc -l)
    [[ -n "$volumes" ]] && volume_count=$(echo "$volumes" | wc -l)
    [[ -n "$networks" ]] && network_count=$(echo "$networks" | wc -l)
    [[ -n "$firewalls" ]] && firewall_count=$(echo "$firewalls" | wc -l)
    
    local total_count=$((server_count + volume_count + network_count + firewall_count))
    
    if [[ $total_count -eq 0 ]]; then
        log_info "No Hetzner resources found with prefix '$PREFIX_FILTER'"
        return 0
    fi
    
    echo ""
    echo "Total: $server_count server(s), $volume_count volume(s), $network_count network(s), $firewall_count firewall(s)"
    
    if ! confirm_deletion "$total_count" "Hetzner"; then
        return 0
    fi
    
    log_info "Deleting Hetzner resources..."
    
    # Delete servers first
    local server_list
    server_list=$(hcloud server list -o noheader -o columns=name 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting server: $name"
            hcloud server delete "$name" 2>/dev/null || \
                log_warn "  Failed to delete server: $name"
        fi
    done <<< "$server_list"
    
    # Delete volumes
    local volume_list
    volume_list=$(hcloud volume list -o noheader -o columns=name 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting volume: $name"
            hcloud volume delete "$name" 2>/dev/null || \
                log_warn "  Failed to delete volume: $name"
        fi
    done <<< "$volume_list"
    
    # Delete firewalls
    local firewall_list
    firewall_list=$(hcloud firewall list -o noheader -o columns=name 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting firewall: $name"
            hcloud firewall delete "$name" 2>/dev/null || \
                log_warn "  Failed to delete firewall: $name"
        fi
    done <<< "$firewall_list"
    
    # Delete networks (must be last)
    local network_list
    network_list=$(hcloud network list -o noheader -o columns=name 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting network: $name"
            hcloud network delete "$name" 2>/dev/null || \
                log_warn "  Failed to delete network: $name"
        fi
    done <<< "$network_list"
    
    log_info "Hetzner cleanup completed"
}


# ============================================================================
# DigitalOcean Cleanup
# ============================================================================
cleanup_digitalocean() {
    check_cli_tool "doctl" "Install: https://docs.digitalocean.com/reference/doctl/"
    
    log_info "Fetching DigitalOcean resources with prefix '$PREFIX_FILTER'..."
    
    # Check if authenticated
    if ! doctl account get &>/dev/null; then
        die "Not authenticated with DigitalOcean. Run: doctl auth init"
    fi
    
    # List droplets
    local droplets
    droplets=$(doctl compute droplet list --format Name,Status,PublicIPv4 --no-header 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    
    # List volumes
    local volumes
    volumes=$(doctl compute volume list --format Name,Size,DropletIDs --no-header 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    
    # List VPCs
    local vpcs
    vpcs=$(doctl vpcs list --format Name,Region --no-header 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    
    # List firewalls
    local firewalls
    firewalls=$(doctl compute firewall list --format Name,Status --no-header 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    
    echo ""
    echo "=== DIGITALOCEAN RESOURCES ==="
    
    if [[ -n "$droplets" ]]; then
        echo ""
        echo "Droplets:"
        doctl compute droplet list --format Name,Status,PublicIPv4 2>/dev/null | grep -E "(Name|^${PREFIX_FILTER})" || true
    fi
    
    if [[ -n "$volumes" ]]; then
        echo ""
        echo "Volumes:"
        doctl compute volume list --format Name,Size,DropletIDs 2>/dev/null | grep -E "(Name|^${PREFIX_FILTER})" || true
    fi
    
    if [[ -n "$vpcs" ]]; then
        echo ""
        echo "VPCs:"
        doctl vpcs list --format Name,Region 2>/dev/null | grep -E "(Name|^${PREFIX_FILTER})" || true
    fi
    
    if [[ -n "$firewalls" ]]; then
        echo ""
        echo "Firewalls:"
        doctl compute firewall list --format Name,Status 2>/dev/null | grep -E "(Name|^${PREFIX_FILTER})" || true
    fi
    
    # Count resources
    local droplet_count=0
    local volume_count=0
    local vpc_count=0
    local firewall_count=0
    [[ -n "$droplets" ]] && droplet_count=$(echo "$droplets" | wc -l)
    [[ -n "$volumes" ]] && volume_count=$(echo "$volumes" | wc -l)
    [[ -n "$vpcs" ]] && vpc_count=$(echo "$vpcs" | wc -l)
    [[ -n "$firewalls" ]] && firewall_count=$(echo "$firewalls" | wc -l)
    
    local total_count=$((droplet_count + volume_count + vpc_count + firewall_count))
    
    if [[ $total_count -eq 0 ]]; then
        log_info "No DigitalOcean resources found with prefix '$PREFIX_FILTER'"
        return 0
    fi
    
    echo ""
    echo "Total: $droplet_count droplet(s), $volume_count volume(s), $vpc_count VPC(s), $firewall_count firewall(s)"
    
    if ! confirm_deletion "$total_count" "DigitalOcean"; then
        return 0
    fi
    
    log_info "Deleting DigitalOcean resources..."
    
    # Delete droplets first
    local droplet_list
    droplet_list=$(doctl compute droplet list --format ID,Name --no-header 2>/dev/null | awk "\$2 ~ /^${PREFIX_FILTER}/" || echo "")
    while read -r id name; do
        if [[ -n "$id" && -n "$name" ]]; then
            log_info "  Deleting droplet: $name (ID: $id)"
            doctl compute droplet delete "$id" --force 2>/dev/null || \
                log_warn "  Failed to delete droplet: $name"
        fi
    done <<< "$droplet_list"
    
    # Wait a bit for droplets to be deleted
    if [[ -n "$droplet_list" ]]; then
        log_info "  Waiting for droplets to be deleted..."
        sleep 5
    fi
    
    # Delete volumes
    local volume_list
    volume_list=$(doctl compute volume list --format ID,Name --no-header 2>/dev/null | awk "\$2 ~ /^${PREFIX_FILTER}/" || echo "")
    while read -r id name; do
        if [[ -n "$id" && -n "$name" ]]; then
            log_info "  Deleting volume: $name (ID: $id)"
            doctl compute volume delete "$id" --force 2>/dev/null || \
                log_warn "  Failed to delete volume: $name"
        fi
    done <<< "$volume_list"
    
    # Delete firewalls
    local firewall_list
    firewall_list=$(doctl compute firewall list --format ID,Name --no-header 2>/dev/null | awk "\$2 ~ /^${PREFIX_FILTER}/" || echo "")
    while read -r id name; do
        if [[ -n "$id" && -n "$name" ]]; then
            log_info "  Deleting firewall: $name (ID: $id)"
            doctl compute firewall delete "$id" --force 2>/dev/null || \
                log_warn "  Failed to delete firewall: $name"
        fi
    done <<< "$firewall_list"
    
    # Delete VPCs (must be last)
    local vpc_list
    vpc_list=$(doctl vpcs list --format ID,Name --no-header 2>/dev/null | awk "\$2 ~ /^${PREFIX_FILTER}/" || echo "")
    while read -r id name; do
        if [[ -n "$id" && -n "$name" ]]; then
            log_info "  Deleting VPC: $name (ID: $id)"
            doctl vpcs delete "$id" --force 2>/dev/null || \
                log_warn "  Failed to delete VPC: $name"
        fi
    done <<< "$vpc_list"
    
    log_info "DigitalOcean cleanup completed"
}


# ============================================================================
# Libvirt Cleanup
# ============================================================================
cleanup_libvirt() {
    check_cli_tool "virsh" "Install libvirt-client package"
    
    log_info "Fetching libvirt resources with prefix '$PREFIX_FILTER'..."
    
    # Determine libvirt URI
    local libvirt_uri="${LIBVIRT_DEFAULT_URI:-qemu:///system}"
    log_info "Using libvirt URI: $libvirt_uri"
    
    # List domains (VMs)
    local domains
    domains=$(virsh -c "$libvirt_uri" list --all --name 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    
    # List volumes
    local volumes
    volumes=$(virsh -c "$libvirt_uri" vol-list default 2>/dev/null | tail -n +3 | grep "${PREFIX_FILTER}" | awk '{print $1}' || echo "")
    
    # List networks
    local networks
    networks=$(virsh -c "$libvirt_uri" net-list --all --name 2>/dev/null | grep "^${PREFIX_FILTER}" || echo "")
    
    echo ""
    echo "=== LIBVIRT RESOURCES (URI: $libvirt_uri) ==="
    
    if [[ -n "$domains" ]]; then
        echo ""
        echo "Domains (VMs):"
        virsh -c "$libvirt_uri" list --all 2>/dev/null | grep -E "(Id|${PREFIX_FILTER})" || true
    fi
    
    if [[ -n "$volumes" ]]; then
        echo ""
        echo "Volumes:"
        virsh -c "$libvirt_uri" vol-list default 2>/dev/null | grep -E "(Name|${PREFIX_FILTER})" || true
    fi
    
    if [[ -n "$networks" ]]; then
        echo ""
        echo "Networks:"
        virsh -c "$libvirt_uri" net-list --all 2>/dev/null | grep -E "(Name|${PREFIX_FILTER})" || true
    fi
    
    # Count resources
    local domain_count=0
    local volume_count=0
    local network_count=0
    [[ -n "$domains" ]] && domain_count=$(echo "$domains" | grep -c . || echo "0")
    [[ -n "$volumes" ]] && volume_count=$(echo "$volumes" | grep -c . || echo "0")
    [[ -n "$networks" ]] && network_count=$(echo "$networks" | grep -c . || echo "0")
    
    local total_count=$((domain_count + volume_count + network_count))
    
    if [[ $total_count -eq 0 ]]; then
        log_info "No libvirt resources found with prefix '$PREFIX_FILTER'"
        return 0
    fi
    
    echo ""
    echo "Total: $domain_count domain(s), $volume_count volume(s), $network_count network(s)"
    
    if ! confirm_deletion "$total_count" "libvirt"; then
        return 0
    fi
    
    log_info "Deleting libvirt resources..."
    
    # Delete domains first
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting domain: $name"
            # Destroy (stop) if running
            virsh -c "$libvirt_uri" destroy "$name" 2>/dev/null || true
            # Undefine (delete)
            virsh -c "$libvirt_uri" undefine "$name" --remove-all-storage 2>/dev/null || \
                log_warn "  Failed to delete domain: $name"
        fi
    done <<< "$domains"
    
    # Delete volumes
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting volume: $name"
            virsh -c "$libvirt_uri" vol-delete "$name" --pool default 2>/dev/null || \
                log_warn "  Failed to delete volume: $name"
        fi
    done <<< "$volumes"
    
    # Delete networks
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting network: $name"
            # Destroy (stop) if active
            virsh -c "$libvirt_uri" net-destroy "$name" 2>/dev/null || true
            # Undefine (delete)
            virsh -c "$libvirt_uri" net-undefine "$name" 2>/dev/null || \
                log_warn "  Failed to delete network: $name"
        fi
    done <<< "$networks"
    
    log_info "Libvirt cleanup completed"
}

# ============================================================================
# Main execution
# ============================================================================

log_info "Starting cleanup for provider: $PROVIDER"

case "$PROVIDER" in
    aws)
        cleanup_aws
        ;;
    azure)
        cleanup_azure
        ;;
    gcp)
        cleanup_gcp
        ;;
    hetzner)
        cleanup_hetzner
        ;;
    digitalocean)
        cleanup_digitalocean
        ;;
    libvirt)
        cleanup_libvirt
        ;;
esac

log_info "Cleanup process completed"
