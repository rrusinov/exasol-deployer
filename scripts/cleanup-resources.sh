#!/usr/bin/env bash
# Unified cloud resource cleanup script for Exasol Deployer
# Supports: AWS, Azure, GCP, Hetzner, DigitalOcean, Exoscale, Libvirt

set -euo pipefail

# Source library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/oci-utils.sh"
source "$SCRIPT_DIR/lib/aws-utils.sh"
source "$SCRIPT_DIR/lib/azure-utils.sh"
source "$SCRIPT_DIR/lib/gcp-utils.sh"
source "$SCRIPT_DIR/lib/hetzner-utils.sh"

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
  --provider <PROVIDER>    Cloud provider: aws, azure, gcp, hetzner, digitalocean, exoscale, libvirt

Optional:
  --tag <TAG>             Filter resources by tag/label (default: owner=exasol-deployer)
  --prefix <PREFIX>       Filter resources by name prefix (default: empty)
  --region <REGION>       AWS region (default: AWS_DEFAULT_REGION or us-east-1)
  --dry-run               Show what would be deleted without deleting
  --yes                   Skip confirmation prompt
  --unused-vpc            Clean up unused/empty VPCs (AWS only)
  --help                  Show this help message

Examples:
  # List all Azure resources
  $0 --provider azure --dry-run

  # Delete all Hetzner resources with confirmation
  $0 --provider hetzner


  # Delete AWS resources in specific region
  $0 --provider aws --region us-east-2 --yes

  # Delete GCP resources without confirmation
  $0 --provider gcp --yes

  # Delete DigitalOcean resources with custom prefix
  $0 --provider digitalocean --prefix myapp

  # Clean up unused VPCs in AWS (all regions)
  $0 --provider aws --unused-vpc --yes

EOF
    exit 0
}

# Parse command line arguments
PROVIDER=""
TAG_FILTER="owner=exasol-deployer"
PREFIX_FILTER=""
AWS_REGION=""
DRY_RUN=false
SKIP_CONFIRM=false
CLEANUP_UNUSED_VPC=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --provider)
            [[ -z "${2:-}" ]] && die "--provider requires a value"
            PROVIDER="$2"
            shift 2
            ;;
        --tag)
            TAG_FILTER="${2:-}"
            shift 2
            ;;
        --prefix)
            [[ -z "${2:-}" ]] && die "--prefix requires a value"
            PREFIX_FILTER="$2"
            shift 2
            ;;
        --region)
            [[ -z "${2:-}" ]] && die "--region requires a value"
            AWS_REGION="$2"
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
        --unused-vpc)
            CLEANUP_UNUSED_VPC=true
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
    aws|azure|gcp|oci|hetzner|digitalocean|exoscale|libvirt)
        ;;
    *)
        die "Unsupported provider: $PROVIDER. Supported: aws, azure, gcp, hetzner, digitalocean, exoscale, libvirt"
        ;;
esac

# Validate feature support per provider
if [[ -n "$AWS_REGION" && "$PROVIDER" != "aws" ]]; then
    die "--region flag is only supported for AWS provider"
fi

if [[ "$TAG_FILTER" != "owner=exasol-deployer" && "$PROVIDER" != "aws" ]]; then
    die "--tag filtering is only supported for AWS provider (other providers use resource groups or global listing)"
fi

if [[ "$CLEANUP_UNUSED_VPC" == true && "$PROVIDER" != "aws" ]]; then
    die "--unused-vpc is only supported for AWS provider"
fi

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
# AWS Unused VPC Detection and Cleanup
# ============================================================================

# Detect unused VPCs in a region and store them in global arrays
detect_unused_aws_vpcs() {
    local region="$1"
    
    log_info "Checking for unused VPCs in region: $region"
    
    # Get all VPCs in the region
    local all_vpcs
    # shellcheck disable=SC2016
    all_vpcs=$(aws ec2 describe-vpcs --region "$region" \
        --query 'Vpcs[].[VpcId,Tags[?Key==`Name`].Value|[0],IsDefault]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$all_vpcs" ]]; then
        return 0
    fi
    
    # Process each VPC
    while IFS=$'\t' read -r vpc_id vpc_name is_default; do
        # Skip default VPCs
        if [[ "$is_default" == "True" ]]; then
            continue
        fi
        
        # Check if VPC has any instances
        local instance_count
        instance_count=$(aws ec2 describe-instances --region "$region" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'length(Reservations[].Instances[])' \
            --output text 2>/dev/null || echo "0")
        
        # Check if VPC has any network interfaces (all types, not just instance-attached)
        local eni_count
        eni_count=$(aws ec2 describe-network-interfaces --region "$region" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'length(NetworkInterfaces[])' \
            --output text 2>/dev/null || echo "0")
        
        # Check RDS instances
        local rds_count
        rds_count=$(aws rds describe-db-instances --region "$region" \
            --query "length(DBInstances[?DBSubnetGroup.VpcId=='$vpc_id'])" \
            --output text 2>/dev/null || echo "0")
        
        # Check Lambda functions
        local lambda_count
        lambda_count=$(aws lambda list-functions --region "$region" \
            --query "length(Functions[?VpcConfig.VpcId=='$vpc_id'])" \
            --output text 2>/dev/null || echo "0")
        
        # Check Load Balancers
        local lb_count
        lb_count=$(aws elbv2 describe-load-balancers --region "$region" \
            --query "length(LoadBalancers[?VpcId=='$vpc_id'])" \
            --output text 2>/dev/null || echo "0")
        
        # Check NAT Gateways
        local nat_count
        nat_count=$(aws ec2 describe-nat-gateways --region "$region" \
            --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
            --query 'length(NatGateways[])' \
            --output text 2>/dev/null || echo "0")
        
        # Check VPC Endpoints
        local vpce_count
        vpce_count=$(aws ec2 describe-vpc-endpoints --region "$region" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'length(VpcEndpoints[])' \
            --output text 2>/dev/null || echo "0")
        
        # Check EFS File Systems (they create ENIs but good to check explicitly)
        local efs_count
        efs_count=$(aws efs describe-mount-targets --region "$region" 2>/dev/null | \
            jq "[.MountTargets[] | select(.VpcId==\"$vpc_id\")] | length" 2>/dev/null || echo "0")
        
        # VPC is unused if it has no resources
        if [[ "$instance_count" == "0" && "$eni_count" == "0" && "$rds_count" == "0" && \
              "$lambda_count" == "0" && "$lb_count" == "0" && "$nat_count" == "0" && \
              "$vpce_count" == "0" && "$efs_count" == "0" ]]; then
            UNUSED_VPCS+=("$region:$vpc_id")
            UNUSED_VPC_NAMES["$region:$vpc_id"]="${vpc_name:-<no name>}"
        fi
        
    done <<< "$all_vpcs"
}

# Delete a VPC and all its dependencies
delete_vpc_with_dependencies() {
    local region="$1"
    local vpc_id="$2"
    
    log_info "Deleting VPC: $vpc_id (region: $region)"
    
    # 1. Delete VPC Endpoints
    local vpc_endpoints
    vpc_endpoints=$(aws ec2 describe-vpc-endpoints --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$vpc_endpoints" ]]; then
        for vpce in $vpc_endpoints; do
            log_info "  Deleting VPC Endpoint: $vpce"
            aws ec2 delete-vpc-endpoints --region "$region" --vpc-endpoint-ids "$vpce" >/dev/null 2>&1 || true
        done
    fi
    
    # 2. Delete NAT Gateways
    local nat_gateways
    nat_gateways=$(aws ec2 describe-nat-gateways --region "$region" \
        --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
        --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$nat_gateways" ]]; then
        for nat_gw in $nat_gateways; do
            log_info "  Deleting NAT Gateway: $nat_gw"
            aws ec2 delete-nat-gateway --region "$region" --nat-gateway-id "$nat_gw" 2>/dev/null || true
        done
        
        # Wait for NAT gateways to be deleted
        if [[ -n "$nat_gateways" ]]; then
            log_info "  Waiting for NAT Gateways to be deleted..."
            sleep 10
        fi
    fi
    
    # 3. Release Elastic IPs associated with the VPC
    local eips
    eips=$(aws ec2 describe-addresses --region "$region" \
        --filters "Name=domain,Values=vpc" \
        --query "Addresses[?NetworkInterfaceOwnerId!=null].AllocationId" --output text 2>/dev/null || echo "")
    
    if [[ -n "$eips" ]]; then
        for eip in $eips; do
            # Check if EIP is associated with this VPC
            local eip_vpc
            eip_vpc=$(aws ec2 describe-network-interfaces --region "$region" \
                --filters "Name=addresses.allocation-id,Values=$eip" \
                --query 'NetworkInterfaces[0].VpcId' --output text 2>/dev/null || echo "")
            
            if [[ "$eip_vpc" == "$vpc_id" ]]; then
                log_info "  Releasing Elastic IP: $eip"
                aws ec2 release-address --region "$region" --allocation-id "$eip" 2>/dev/null || true
            fi
        done
    fi
    
    # 4. Delete all network interfaces (except primary ones)
    local enis
    enis=$(aws ec2 describe-network-interfaces --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$enis" ]]; then
        for eni in $enis; do
            log_info "  Deleting network interface: $eni"
            aws ec2 delete-network-interface --region "$region" --network-interface-id "$eni" 2>/dev/null || true
        done
    fi
    
    # 5. Delete Internet Gateways
    local igws
    igws=$(aws ec2 describe-internet-gateways --region "$region" \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$igws" ]]; then
        for igw in $igws; do
            log_info "  Detaching and deleting Internet Gateway: $igw"
            aws ec2 detach-internet-gateway --region "$region" --internet-gateway-id "$igw" --vpc-id "$vpc_id" 2>/dev/null || true
            aws ec2 delete-internet-gateway --region "$region" --internet-gateway-id "$igw" 2>/dev/null || true
        done
    fi
    
    # 6. Delete subnets
    local subnets
    subnets=$(aws ec2 describe-subnets --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$subnets" ]]; then
        for subnet in $subnets; do
            log_info "  Deleting subnet: $subnet"
            aws ec2 delete-subnet --region "$region" --subnet-id "$subnet" 2>/dev/null || true
        done
    fi
    
    # 7. Delete route tables (non-main)
    local route_tables
    # shellcheck disable=SC2016
    route_tables=$(aws ec2 describe-route-tables --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$route_tables" ]]; then
        for rt in $route_tables; do
            log_info "  Deleting route table: $rt"
            aws ec2 delete-route-table --region "$region" --route-table-id "$rt" 2>/dev/null || true
        done
    fi
    
    # 8. Delete security groups (non-default)
    local security_groups
    # shellcheck disable=SC2016
    security_groups=$(aws ec2 describe-security-groups --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$security_groups" ]]; then
        for sg in $security_groups; do
            log_info "  Deleting security group: $sg"
            aws ec2 delete-security-group --region "$region" --group-id "$sg" >/dev/null 2>&1 || true
        done
    fi
    
    # 9. Delete network ACLs (non-default)
    local network_acls
    # shellcheck disable=SC2016
    network_acls=$(aws ec2 describe-network-acls --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'NetworkAcls[?IsDefault!=`true`].NetworkAclId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$network_acls" ]]; then
        for acl in $network_acls; do
            log_info "  Deleting network ACL: $acl"
            aws ec2 delete-network-acl --region "$region" --network-acl-id "$acl" 2>/dev/null || true
        done
    fi
    
    # 10. Finally, delete the VPC
    log_info "  Deleting VPC: $vpc_id"
    if aws ec2 delete-vpc --region "$region" --vpc-id "$vpc_id" 2>/dev/null; then
        log_info "  ✓ VPC deleted successfully: $vpc_id"
    else
        log_warn "  Failed to delete VPC: $vpc_id (may still have dependencies)"
    fi
}

# ============================================================================
# AWS Cleanup
# ============================================================================
cleanup_aws() {
    check_cli_tool "aws" "Install: https://aws.amazon.com/cli/"
    
    # Disable AWS CLI pager
    export AWS_PAGER=""
    
    # Get regions to scan
    local regions
    if [[ -n "$AWS_REGION" ]]; then
        regions=("$AWS_REGION")
        log_info "Using AWS region: $AWS_REGION"
    else
        regions=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-central-1" "ap-southeast-1" "ap-northeast-1")
        log_info "Scanning all AWS regions..."
    fi
    
    # If cleaning up unused VPCs, do that and exit
    if [[ "$CLEANUP_UNUSED_VPC" == true ]]; then
        log_info "Detecting unused AWS VPCs..."
        
        # Global arrays to collect unused VPCs across regions
        declare -a UNUSED_VPCS=()
        declare -A UNUSED_VPC_NAMES=()
        
        # Detect unused VPCs in all regions
        for region in "${regions[@]}"; do
            detect_unused_aws_vpcs "$region"
        done
        
        if [[ ${#UNUSED_VPCS[@]} -eq 0 ]]; then
            log_info "No unused VPCs found in any region"
            return 0
        fi
        
        # Display all unused VPCs
        echo ""
        echo "=== UNUSED VPCs ACROSS ALL REGIONS ==="
        echo ""
        printf "%-15s %-20s %-40s\n" "Region" "VPC ID" "Name"
        printf "%-15s %-20s %-40s\n" "---------------" "--------------------" "----------------------------------------"
        
        for vpc_key in "${UNUSED_VPCS[@]}"; do
            local region="${vpc_key%%:*}"
            local vpc_id="${vpc_key#*:}"
            printf "%-15s %-20s %-40s\n" "$region" "$vpc_id" "${UNUSED_VPC_NAMES[$vpc_key]}"
        done
        
        echo ""
        echo "Total unused VPCs: ${#UNUSED_VPCS[@]}"
        
        # Confirm deletion
        if ! confirm_deletion "${#UNUSED_VPCS[@]} unused VPC(s)" "AWS"; then
            return 0
        fi
        
        # Delete all unused VPCs
        log_info "Deleting unused VPCs..."
        for vpc_key in "${UNUSED_VPCS[@]}"; do
            local region="${vpc_key%%:*}"
            local vpc_id="${vpc_key#*:}"
            delete_vpc_with_dependencies "$region" "$vpc_id"
        done
        
        log_info "Unused VPC cleanup completed"
        return 0
    fi
    
    log_info "Fetching AWS resources with tag '$TAG_FILTER' and prefix '$PREFIX_FILTER'..."
    
    # Get regions to scan
    local regions
    if [[ -n "$AWS_REGION" ]]; then
        regions=("$AWS_REGION")
        log_info "Using AWS region: $AWS_REGION"
    else
        regions=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-central-1" "ap-southeast-1" "ap-northeast-1")
        log_info "Scanning all AWS regions..."
    fi
    
    local found_resources=false
    
    # Parse tag filter (format: key=value)
    local tag_key="" tag_value=""
    if [[ -n "$TAG_FILTER" && "$TAG_FILTER" == *"="* ]]; then
        tag_key="${TAG_FILTER%%=*}"
        tag_value="${TAG_FILTER#*=}"
    fi
    
    for region in "${regions[@]}"; do
        # Build filters for VPC discovery
        local filter_args=("Name=tag:Name,Values=${PREFIX_FILTER}*")
        if [[ -n "$tag_key" ]]; then
            filter_args+=("Name=tag:${tag_key},Values=${tag_value}")
        fi
        
        # Find VPCs with filters
        local vpcs
        vpcs=$(aws ec2 describe-vpcs --region "$region" \
            --filters "${filter_args[@]}" \
            --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
        
        if [[ -z "$vpcs" ]]; then
            continue
        fi
        
        found_resources=true
        
        echo ""
        echo "=== AWS RESOURCES (Region: $region) ==="
        
        for vpc in $vpcs; do
            echo ""
            echo "VPC: $vpc"
            
            # List spot instance requests
            local spot_reqs
            spot_reqs=$(aws ec2 describe-spot-instance-requests --region "$region" \
                --filters "Name=state,Values=open,active" \
                --query 'SpotInstanceRequests[].[SpotInstanceRequestId,State,InstanceId]' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$spot_reqs" ]]; then
                echo ""
                echo "Active Spot Requests:"
                echo "$spot_reqs" | awk '{printf "  %s (%s) - Instance: %s\n", $1, $2, $3}'
            fi
            
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
    done
    
    if [[ "$found_resources" == "false" ]]; then
        log_info "No AWS VPCs found with prefix '$PREFIX_FILTER' in any region"
        return 0
    fi
    
    if ! confirm_deletion "VPC(s) and associated resources across regions" "AWS"; then
        return 0
    fi
    
    log_info "Deleting AWS resources..."
    for region in "${regions[@]}"; do
        # Cancel all active spot instance requests in this region first
        log_info "Cancelling spot instance requests in $region..."
        local spot_requests
        spot_requests=$(aws ec2 describe-spot-instance-requests --region "$region" \
            --filters "Name=state,Values=open,active" \
            --query 'SpotInstanceRequests[].SpotInstanceRequestId' --output text 2>/dev/null || echo "")
        
        if [[ -n "$spot_requests" ]]; then
            # shellcheck disable=SC2086
            aws ec2 cancel-spot-instance-requests --region "$region" --spot-instance-request-ids $spot_requests 2>/dev/null || true
            log_info "  Cancelled spot requests: $spot_requests"
        fi
        
        local vpcs
        # Parse tag filter (format: key=value)
        local tag_key="${TAG_FILTER%%=*}"
        local tag_value="${TAG_FILTER#*=}"
        
        vpcs=$(aws ec2 describe-vpcs --region "$region" \
            --filters "Name=tag:${tag_key},Values=${tag_value}" \
            --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
        
        # Additional prefix filter if specified
        if [[ -n "$PREFIX_FILTER" ]]; then
            local prefix_vpcs
            prefix_vpcs=$(aws ec2 describe-vpcs --region "$region" \
                --filters "Name=tag:Name,Values=${PREFIX_FILTER}*" \
                --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
            
            # Intersect the two lists
            if [[ -n "$vpcs" && -n "$prefix_vpcs" ]]; then
                vpcs=$(echo "$vpcs $prefix_vpcs" | tr ' ' '\n' | sort | uniq -d | tr '\n' ' ')
            elif [[ -n "$prefix_vpcs" ]]; then
                vpcs="$prefix_vpcs"
            fi
        fi
        
        if [[ -z "$vpcs" ]]; then
            continue
        fi
        
        for vpc in $vpcs; do
            log_info "Deleting VPC: $vpc (region: $region)"
            
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
            
            # Delete VPC with all dependencies
            delete_vpc_with_dependencies "$region" "$vpc"
        done
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
    
    # Build filter based on prefix
    local filter_args=()
    if [[ -n "$PREFIX_FILTER" ]]; then
        filter_args=("--filter=name~^${PREFIX_FILTER}")
    fi
    
    # List instances
    local instances
    instances=$(gcloud compute instances list "${filter_args[@]}" \
        --format="table(name,zone,status)" 2>/dev/null || echo "")
    
    # List disks
    local disks
    disks=$(gcloud compute disks list "${filter_args[@]}" \
        --format="table(name,zone,sizeGb,status)" 2>/dev/null || echo "")
    
    # List networks
    local networks
    networks=$(gcloud compute networks list "${filter_args[@]}" \
        --format="table(name,mode)" 2>/dev/null || echo "")
    
    # List subnets
    local subnets
    subnets=$(gcloud compute networks subnets list "${filter_args[@]}" \
        --format="table(name,region,network,ipCidrRange)" 2>/dev/null || echo "")
    
    # List firewall rules
    local firewalls
    firewalls=$(gcloud compute firewall-rules list "${filter_args[@]}" \
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
    
    if [[ -n "$subnets" ]]; then
        echo ""
        echo "Subnets:"
        echo "$subnets"
    fi
    
    if [[ -n "$firewalls" ]]; then
        echo ""
        echo "Firewall Rules:"
        echo "$firewalls"
    fi
    
    # Count resources
    local instance_count
    instance_count=$(gcloud compute instances list "${filter_args[@]}" --format="value(name)" 2>/dev/null | wc -l)
    local disk_count
    disk_count=$(gcloud compute disks list "${filter_args[@]}" --format="value(name)" 2>/dev/null | wc -l)
    local network_count
    network_count=$(gcloud compute networks list "${filter_args[@]}" --format="value(name)" 2>/dev/null | wc -l)
    local subnet_count
    subnet_count=$(gcloud compute networks subnets list "${filter_args[@]}" --format="value(name)" 2>/dev/null | wc -l)
    
    local total_count=$((instance_count + disk_count + network_count + subnet_count))
    
    if [[ $total_count -eq 0 ]]; then
        log_info "No GCP resources found with prefix '$PREFIX_FILTER'"
        return 0
    fi
    
    echo ""
    echo "Total: $instance_count instance(s), $disk_count disk(s), $subnet_count subnet(s), $network_count network(s)"
    
    if ! confirm_deletion "$total_count" "GCP"; then
        return 0
    fi
    
    log_info "Deleting GCP resources..."
    
    # Delete instances first
    local instance_list
    instance_list=$(gcloud compute instances list "${filter_args[@]}" --format="value(name,zone)" 2>/dev/null || echo "")
    while IFS=$'\t' read -r name zone; do
        if [[ -n "$name" && -n "$zone" ]]; then
            log_info "  Deleting instance: $name (zone: $zone)"
            gcloud compute instances delete "$name" --zone="$zone" --quiet 2>/dev/null || \
                log_warn "  Failed to delete instance: $name"
        fi
    done <<< "$instance_list"
    
    # Delete disks
    local disk_list
    disk_list=$(gcloud compute disks list "${filter_args[@]}" --format="value(name,zone)" 2>/dev/null || echo "")
    while IFS=$'\t' read -r name zone; do
        if [[ -n "$name" && -n "$zone" ]]; then
            log_info "  Deleting disk: $name (zone: $zone)"
            gcloud compute disks delete "$name" --zone="$zone" --quiet 2>/dev/null || \
                log_warn "  Failed to delete disk: $name"
        fi
    done <<< "$disk_list"
    
    # Delete firewall rules
    local firewall_list
    firewall_list=$(gcloud compute firewall-rules list "${filter_args[@]}" --format="value(name)" 2>/dev/null || echo "")
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting firewall rule: $name"
            gcloud compute firewall-rules delete "$name" --quiet 2>/dev/null || \
                log_warn "  Failed to delete firewall rule: $name"
        fi
    done <<< "$firewall_list"
    
    # Delete subnets (must be before networks)
    local subnet_list
    subnet_list=$(gcloud compute networks subnets list "${filter_args[@]}" --format="value(name,region)" 2>/dev/null || echo "")
    while IFS=$'\t' read -r name region; do
        if [[ -n "$name" && -n "$region" ]]; then
            log_info "  Deleting subnet: $name (region: $region)"
            gcloud compute networks subnets delete "$name" --region="$region" --quiet 2>/dev/null || \
                log_warn "  Failed to delete subnet: $name"
        fi
    done <<< "$subnet_list"
    
    # Delete networks (must be last)
    local network_list
    network_list=$(gcloud compute networks list "${filter_args[@]}" --format="value(name)" 2>/dev/null || echo "")
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
    
    # List VPCs (excluding default VPCs which cannot be deleted)
    local vpcs
    vpcs=$(doctl vpcs list --format Name,Region,Default --no-header 2>/dev/null | grep "^${PREFIX_FILTER}" | grep -v "true$" || echo "")
    
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
    
    # Delete VPCs (must be last, skip default VPCs)
    local vpc_list
    vpc_list=$(doctl vpcs list --format ID,Name,Default --no-header 2>/dev/null | awk "\$2 ~ /^${PREFIX_FILTER}/ && \$3 != \"true\"" || echo "")
    while read -r id name default; do
        if [[ -n "$id" && -n "$name" ]]; then
            log_info "  Deleting VPC: $name (ID: $id)"
            doctl vpcs delete "$id" --force 2>/dev/null || \
                log_warn "  Failed to delete VPC: $name"
        fi
    done <<< "$vpc_list"
    
    log_info "DigitalOcean cleanup completed"
}


# ============================================================================
# Exoscale Cleanup
# ============================================================================
cleanup_exoscale() {
    check_cli_tool "exo" "Install: https://github.com/exoscale/cli"
    
    log_info "Fetching Exoscale resources with prefix '$PREFIX_FILTER'..."
    
    # Check if authenticated
    if ! exo config show &>/dev/null; then
        die "Not authenticated with Exoscale. Run: exo config"
    fi
    
    # Test API connectivity
    local api_test
    api_test=$(exo compute instance list --zone ch-gva-2 -O json 2>&1)
    if echo "$api_test" | grep -qi "not found\|404\|error"; then
        log_error "Exoscale API error detected. The exo CLI may have compatibility issues."
        log_error "API response: $(echo "$api_test" | head -2)"
        log_warn "Workaround: Use 'exasol destroy' from your deployment directory instead."
        return 1
    fi
    
    # Get default zone from config (or use ch-gva-2 as fallback)
    local default_zone
    default_zone=$(exo config show 2>/dev/null | grep "Default Zone" | awk '{print $4}' || echo "ch-gva-2")
    
    # List instances across all zones
    local instances=""
    local volumes=""
    local security_groups=""
    local ssh_keys=""
    
    # Query each zone
    for zone in ch-gva-2 ch-dk-2 de-fra-1 de-muc-1 at-vie-1 bg-sof-1; do
        local zone_instances
        zone_instances=$(exo compute instance list --zone "$zone" -O json 2>/dev/null | \
            jq -r ".[] | select(.name | startswith(\"${PREFIX_FILTER}\")) | \"\(.name):\(.id):$zone\"" 2>/dev/null || echo "")
        
        if [[ -n "$zone_instances" ]]; then
            instances="${instances}${zone_instances}"$'\n'
        fi
        
        # List block storage volumes
        local zone_volumes
        zone_volumes=$(exo storage block list --zone "$zone" -O json 2>/dev/null | \
            jq -r ".[] | select(.name | startswith(\"${PREFIX_FILTER}\")) | \"\(.name):\(.id):$zone\"" 2>/dev/null || echo "")
        
        if [[ -n "$zone_volumes" ]]; then
            volumes="${volumes}${zone_volumes}"$'\n'
        fi
    done
    
    # List security groups (global)
    security_groups=$(exo compute security-group list -O json 2>/dev/null | \
        jq -r ".[] | select(.name | startswith(\"${PREFIX_FILTER}\")) | \"\(.name):\(.id)\"" 2>/dev/null || echo "")
    
    # List SSH keys (global)
    ssh_keys=$(exo compute ssh-key list -O json 2>/dev/null | \
        jq -r ".[] | select(.name | startswith(\"${PREFIX_FILTER}\")) | \"\(.name)\"" 2>/dev/null || echo "")
    
    echo ""
    echo "=== EXOSCALE RESOURCES ==="
    
    if [[ -n "$instances" ]]; then
        echo ""
        echo "Instances:"
        echo "$instances" | awk -F: '{if ($1) print "  " $3 ": " $1 " (" $2 ")"}'
    fi
    
    if [[ -n "$volumes" ]]; then
        echo ""
        echo "Block Storage Volumes:"
        echo "$volumes" | awk -F: '{if ($1) print "  " $3 ": " $1 " (" $2 ")"}'
    fi
    
    if [[ -n "$security_groups" ]]; then
        echo ""
        echo "Security Groups:"
        echo "$security_groups" | awk -F: '{if ($1) print "  " $1 " (" $2 ")"}'
    fi
    
    if [[ -n "$ssh_keys" ]]; then
        echo ""
        echo "SSH Keys:"
        echo "$ssh_keys" | awk '{if ($1) print "  " $1}'
    fi
    
    # Count resources
    local instance_count=0
    local volume_count=0
    local sg_count=0
    local key_count=0
    [[ -n "$instances" ]] && instance_count=$(echo "$instances" | grep -c ":" || echo "0")
    [[ -n "$volumes" ]] && volume_count=$(echo "$volumes" | grep -c ":" || echo "0")
    [[ -n "$security_groups" ]] && sg_count=$(echo "$security_groups" | grep -c ":" || echo "0")
    [[ -n "$ssh_keys" ]] && key_count=$(echo "$ssh_keys" | grep -c . || echo "0")
    
    local total_count=$((instance_count + volume_count + sg_count + key_count))
    
    if [[ $total_count -eq 0 ]]; then
        log_info "No Exoscale resources found with prefix '$PREFIX_FILTER'"
        return 0
    fi
    
    echo ""
    echo "Total: $instance_count instance(s), $volume_count volume(s), $sg_count security group(s), $key_count SSH key(s)"
    
    if ! confirm_deletion "$total_count" "Exoscale"; then
        return 0
    fi
    
    log_info "Deleting Exoscale resources..."
    
    # Stop and delete instances first
    local instances_to_delete=()
    while IFS=: read -r name id zone; do
        if [[ -n "$name" && -n "$id" && -n "$zone" ]]; then
            log_info "  Stopping instance: $name in zone $zone (ID: $id)"
            exo compute instance stop "$id" --zone "$zone" --force 2>/dev/null || \
                log_warn "  Failed to stop instance: $name (may already be stopped)"
            instances_to_delete+=("$name:$id:$zone")
        fi
    done <<< "$instances"
    
    # Wait for instances to be stopped
    if [[ ${#instances_to_delete[@]} -gt 0 ]]; then
        log_info "  Waiting for instances to stop..."
        sleep 15
        
        # Now delete the stopped instances
        for instance_info in "${instances_to_delete[@]}"; do
            IFS=: read -r name id zone <<< "$instance_info"
            log_info "  Deleting instance: $name in zone $zone (ID: $id)"
            exo compute instance delete "$id" --zone "$zone" --force 2>/dev/null || \
                log_warn "  Failed to delete instance: $name"
        done
    fi
    
    # Wait for instances to be deleted
    if [[ -n "$instances" ]]; then
        log_info "  Waiting for instances to be deleted..."
        sleep 10
    fi
    
    # Delete volumes
    while IFS=: read -r name id zone; do
        if [[ -n "$name" && -n "$id" && -n "$zone" ]]; then
            log_info "  Deleting volume: $name in zone $zone (ID: $id)"
            exo storage block delete "$id" --zone "$zone" --force 2>/dev/null || \
                log_warn "  Failed to delete volume: $name"
        fi
    done <<< "$volumes"
    
    # Delete security groups
    while IFS=: read -r name id; do
        if [[ -n "$name" && -n "$id" ]]; then
            log_info "  Deleting security group: $name (ID: $id)"
            exo compute security-group delete "$id" --force 2>/dev/null || \
                log_warn "  Failed to delete security group: $name"
        fi
    done <<< "$security_groups"
    
    # Delete SSH keys
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            log_info "  Deleting SSH key: $name"
            exo compute ssh-key delete "$name" --force 2>/dev/null || \
                log_warn "  Failed to delete SSH key: $name"
        fi
    done <<< "$ssh_keys"
    
    log_info "Exoscale cleanup completed"
}


# ============================================================================
# OCI Cleanup
# ============================================================================
cleanup_oci() {
    check_cli_tool "oci" "Install: pip install oci-cli"
    
    log_info "Collecting OCI resources with prefix '$PREFIX_FILTER'..."
    
    # Get compartment OCID
    local compartment_ocid
    compartment_ocid=$(get_oci_compartment_ocid)
    
    if [[ -z "$compartment_ocid" ]]; then
        log_error "Could not determine compartment OCID"
        return 1
    fi
    
    # Generate summary and get resource data
    generate_oci_cleanup_summary "$compartment_ocid" "$PREFIX_FILTER"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "DRY RUN: Would delete the above resources"
        return 0
    fi
    
    echo ""
    if [[ "${SKIP_CONFIRM:-false}" != "true" ]]; then
        read -p "Delete all listed OCI resources? [y/N]: " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Aborted by user"
            return 0
        fi
    fi
    
    # Delete instances first
    if [[ -f /tmp/oci_instances.json ]]; then
        local instances_json
        instances_json=$(cat /tmp/oci_instances.json)
        local instance_count
        instance_count=$(echo "$instances_json" | jq '. | length' 2>/dev/null || echo "0")
        
        if [[ "$instance_count" -gt 0 ]]; then
            log_info "Terminating compute instances..."
            echo "$instances_json" | jq -r '.[] | "\(.id):\(.name)"' | while IFS=: read -r id name; do
                if [[ -n "$name" ]]; then
                    terminate_oci_instance "$id" "$name"
                fi
            done
        fi
    fi
    
    # Delete volumes
    if [[ -f /tmp/oci_volumes.json ]]; then
        local volumes_json
        volumes_json=$(cat /tmp/oci_volumes.json)
        local volume_count
        volume_count=$(echo "$volumes_json" | jq '. | length' 2>/dev/null || echo "0")
        
        if [[ "$volume_count" -gt 0 ]]; then
            log_info "Deleting block volumes..."
            echo "$volumes_json" | jq -r '.[] | "\(.id):\(.name)"' | while IFS=: read -r id name; do
                if [[ -n "$name" ]]; then
                    delete_oci_volume "$id" "$name"
                fi
            done
        fi
    fi
    
    # Cleanup temp files
    rm -f /tmp/oci_instances.json /tmp/oci_volumes.json
    
    log_info "OCI cleanup completed"
}
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
    exoscale)
        cleanup_exoscale
        ;;
    oci)
        cleanup_oci
        ;;
    libvirt)
        cleanup_libvirt
        ;;
esac

log_info "Cleanup process completed"
