#!/usr/bin/env bash
# Generate HTML report of cloud resource limits

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global temp directory for cleanup trap
TEMP_DIR=""

# Cleanup function for trap
cleanup_temp() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Generate HTML report of cloud resource limits across all providers and regions.

Options:
  --output <FILE>    Output HTML file (default: limits-report.html)
  --provider <NAME>  Only check specific provider (aws, azure, gcp, hetzner, digitalocean, libvirt)
  --help             Show this help message

Examples:
  $0 --output report.html                      # All providers, all regions
  $0 --provider hetzner --output hetzner.html  # Specific provider

Note: Report scans all major regions by default and shows tags (owner, creator, project).
EOF
    exit 0
}

generate_html_header() {
    cat <<'HTMLHEAD'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="60">
    <title>Cloud Resource Usage & Limits Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 2rem; background: #f5f5f5; }
        h1 { color: #333; border-bottom: 3px solid #4CAF50; padding-bottom: 0.5rem; }
        .header-info { background: #fff; padding: 1rem; border-radius: 5px; margin-bottom: 2rem; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .timestamp { color: #666; font-size: 0.9rem; }
        .provider { background: white; margin-bottom: 1.5rem; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); overflow: hidden; }
        .provider-header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 1rem 1.5rem; cursor: pointer; display: flex; justify-content: space-between; align-items: center; }
        .provider-header:hover { background: linear-gradient(135deg, #5568d3 0%, #653a8b 100%); }
        .provider-header h2 { margin: 0; font-size: 1.2rem; margin-bottom: 0.5rem; }
        .provider-summary { margin-left: 1.5rem; font-size: 0.9rem; opacity: 0.9; }
        .provider-summary .badge { background: rgba(255,255,255,0.2); padding: 4px 8px; border-radius: 4px; margin: 0 4px; }
        .provider-summary .badge.active { background: rgba(255,255,255,0.3); font-weight: bold; }
        .provider-content { padding: 1rem 1.5rem; max-height: 5000px; overflow: hidden; transition: max-height 0.3s ease; }
        .provider-content.collapsed { max-height: 0; padding: 0 1.5rem; }
        .toggle-icon { transition: transform 0.3s; font-size: 1rem; }
        .toggle-icon.expanded { transform: rotate(90deg); }
        .region { margin: 1rem 0; padding: 1rem; background: #f9f9f9; border-radius: 5px; border-left: 4px solid #2196F3; }
        .region h3 { margin-top: 0; color: #2196F3; font-size: 1.1rem; }
        table { width: 100%; border-collapse: collapse; margin: 1rem 0; background: white; }
        th { background: #e0e0e0; padding: 10px; text-align: left; font-weight: bold; border-bottom: 2px solid #ccc; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
        .quota-table th:first-child { width: 40%; }
        .quota-table th:nth-child(2) { width: 20%; text-align: right; }
        .quota-table th:nth-child(3) { width: 20%; text-align: right; }
        .quota-table th:nth-child(4) { width: 20%; text-align: right; }
        .quota-table td:nth-child(2), .quota-table td:nth-child(3), .quota-table td:nth-child(4) { text-align: right; font-family: monospace; }
        .instances-table th:first-child { width: 30%; }
        .warning { color: #ff9800; font-weight: bold; }
    </style>
    <script>
        function toggleProvider(id) {
            const header = document.getElementById(id + '-header');
            const content = document.getElementById(id + '-content');
            const icon = document.getElementById(id + '-icon');
            header.classList.toggle('collapsed');
            content.classList.toggle('collapsed');
            icon.classList.toggle('expanded');
        }
    </script>
</head>
<body>
    <h1>Cloud Resource Usage & Limits Report</h1>
HTMLHEAD
}

generate_html_footer() {
    cat <<'HTMLFOOT'
</body>
</html>
HTMLFOOT
}

collect_aws_data() {
    local region="$1"
    local output_file="$2"
    
    if ! command -v aws &>/dev/null; then
        echo "<p class='warning'>AWS CLI not installed</p>" >> "$output_file"
        return
    fi
    
    cat >> "$output_file" <<EOF
        <div class="region">
            <h3>Region: $region</h3>
            <h4>Resource Quotas</h4>
            <table class="quota-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
EOF
    
    # Get quotas
    local vcpu_limit eip_limit
    vcpu_limit=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --region "$region" --query 'Quota.Value' --output text 2>/dev/null || echo "N/A")
    eip_limit=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-0263D0A3 --region "$region" --query 'Quota.Value' --output text 2>/dev/null || echo "5")
    
    # Get current usage
    local instance_count eip_count vcpu_used
    instance_count=$(aws ec2 describe-instances --region "$region" --filters "Name=instance-state-name,Values=running" --query 'length(Reservations[].Instances[])' --output text 2>/dev/null || echo "0")
    eip_count=$(aws ec2 describe-addresses --region "$region" --query 'length(Addresses)' --output text 2>/dev/null || echo "0")
    vcpu_used="N/A"
    
    # Calculate percentages
    local eip_pct="N/A"
    if [[ "$eip_limit" != "N/A" ]] && [[ "$eip_limit" != "0" ]]; then
        eip_pct=$(awk "BEGIN {printf \"%.1f\", ($eip_count/$eip_limit)*100}")
    fi
    
    cat >> "$output_file" <<EOF
                <tr><td>vCPUs (Standard)</td><td>$vcpu_used</td><td>$vcpu_limit</td><td>-</td></tr>
                <tr><td>Running Instances</td><td>$instance_count</td><td>-</td><td>-</td></tr>
                <tr><td>Public IPs (Elastic)</td><td>$eip_count</td><td>$eip_limit</td><td>$eip_pct%</td></tr>
            </table>
EOF
    
    # List running instances
    if [[ "$instance_count" -gt 0 ]]; then
        {
            cat <<EOF
            <h4>Running Instances</h4>
            <table class="instances-table">
                <tr><th>Instance ID</th><th>Type</th><th>State</th><th>Public IP</th><th>Tags</th></tr>
EOF
            aws ec2 describe-instances --region "$region" \
                --filters "Name=instance-state-name,Values=running" \
                --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,PublicIpAddress,Tags]' \
                --output json 2>/dev/null | jq -r '.[] | 
                    . as $inst | 
                    ($inst[4] // [] | map(select(.Key | test("owner|creator|project"; "i")) | "\(.Key)=\(.Value)") | join(", ")) as $tags |
                    "<tr><td>\($inst[0])</td><td>\($inst[1])</td><td>\($inst[2])</td><td>\($inst[3] // "N/A")</td><td>\($tags)</td></tr>"'
            echo "            </table>"
        } >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}

# Parallel wrapper for AWS regions
collect_aws_data_parallel() {
    local temp_dir="$1"
    local regions=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-central-1" "ap-southeast-1" "ap-northeast-1")
    
    for region in "${regions[@]}"; do
        {
            collect_aws_data "$region" "$temp_dir/aws-$region.html"
        } &
    done
    wait
}

collect_azure_data() {
    local location="$1"
    local output_file="$2"
    
    if ! command -v az &>/dev/null; then
        echo "<p class='warning'>Azure CLI not installed</p>" >> "$output_file"
        return
    fi
    
    cat >> "$output_file" <<EOF
        <div class="region">
            <h3>Location: $location</h3>
            <h4>Resource Quotas</h4>
            <table class="quota-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
EOF
    
    # Get quotas
    local quotas
    quotas=$(az vm list-usage --location "$location" --output json 2>/dev/null)
    
    local vcpu_current vcpu_limit ip_current ip_limit
    vcpu_current=$(echo "$quotas" | jq -r '.[] | select(.name.localizedValue=="Total Regional vCPUs") | .currentValue' 2>/dev/null || echo "0")
    vcpu_limit=$(echo "$quotas" | jq -r '.[] | select(.name.localizedValue=="Total Regional vCPUs") | .limit' 2>/dev/null || echo "N/A")
    
    # Get public IPs for this location
    ip_current=$(az network public-ip list --query "[?location=='$location'] | length(@)" --output tsv 2>/dev/null || echo "0")
    ip_limit=$(az network list-usages --location "$location" --output json 2>/dev/null | jq -r '.[] | select(.name.localizedValue=="Public IP Addresses") | .limit' 2>/dev/null)
    [[ -z "$ip_limit" ]] && ip_limit="N/A"
    
    # Get VM count for this location
    local vm_count
    vm_count=$(az vm list --query "[?location=='$location'] | length(@)" --output tsv 2>/dev/null || echo "0")
    
    # Calculate percentages
    local vcpu_pct="N/A" ip_pct="N/A"
    if [[ "$vcpu_limit" != "N/A" ]] && [[ "$vcpu_limit" != "0" ]]; then
        vcpu_pct=$(awk "BEGIN {printf \"%.1f\", ($vcpu_current/$vcpu_limit)*100}")
    fi
    if [[ "$ip_limit" != "N/A" ]] && [[ "$ip_limit" != "0" ]]; then
        ip_pct=$(awk "BEGIN {printf \"%.1f\", ($ip_current/$ip_limit)*100}")
    fi
    
    cat >> "$output_file" <<EOF
                <tr><td>vCPUs (Regional Total)</td><td>$vcpu_current</td><td>$vcpu_limit</td><td>$vcpu_pct%</td></tr>
                <tr><td>Running Instances</td><td>$vm_count</td><td>-</td><td>-</td></tr>
                <tr><td>Public IPs</td><td>$ip_current</td><td>$ip_limit</td><td>$ip_pct%</td></tr>
            </table>
EOF
    
    # List running VMs in this location
    if [[ "$vm_count" -gt 0 ]]; then
        {
            cat <<EOF
            <h4>Running Virtual Machines</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>Size</th><th>Location</th><th>State</th><th>Tags</th></tr>
EOF
            az vm list --query "[?location=='$location']" --output json 2>/dev/null | jq -r '.[] | 
                (.tags // {} | to_entries | map(select(.key | test("owner|creator|project"; "i")) | "\(.key)=\(.value)") | join(", ")) as $tags |
                "<tr><td>\(.name)</td><td>\(.hardwareProfile.vmSize)</td><td>\(.location)</td><td>\(.provisioningState)</td><td>\($tags)</td></tr>"'
            echo "            </table>"
        } >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}

# Parallel wrapper for Azure locations
collect_azure_data_parallel() {
    local temp_dir="$1"
    local locations=("eastus" "eastus2" "westus" "westus2" "westeurope" "northeurope")
    
    for location in "${locations[@]}"; do
        {
            collect_azure_data "$location" "$temp_dir/azure-$location.html"
        } &
    done
    wait
}

collect_gcp_data() {
    local region="$1"
    local output_file="$2"
    
    if ! command -v gcloud &>/dev/null; then
        echo "<p class='warning'>GCP CLI not installed</p>" >> "$output_file"
        return
    fi
    
    local project
    project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project" ]]; then
        echo "<p class='warning'>No GCP project configured</p>" >> "$output_file"
        return
    fi
    
    cat >> "$output_file" <<EOF
        <div class="region">
            <h3>Region: $region (Project: $project)</h3>
            <h4>Resource Quotas</h4>
            <table class="quota-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
EOF
    
    # Get quotas
    local quotas
    quotas=$(gcloud compute regions describe "$region" --format=json 2>/dev/null)
    
    local cpu_current cpu_limit inst_current inst_limit ip_current ip_limit
    cpu_current=$(echo "$quotas" | jq -r '.quotas[] | select(.metric=="CPUS") | .usage' 2>/dev/null || echo "0")
    cpu_limit=$(echo "$quotas" | jq -r '.quotas[] | select(.metric=="CPUS") | .limit' 2>/dev/null || echo "N/A")
    inst_current=$(echo "$quotas" | jq -r '.quotas[] | select(.metric=="INSTANCES") | .usage' 2>/dev/null || echo "0")
    inst_limit=$(echo "$quotas" | jq -r '.quotas[] | select(.metric=="INSTANCES") | .limit' 2>/dev/null || echo "N/A")
    ip_current=$(echo "$quotas" | jq -r '.quotas[] | select(.metric=="STATIC_ADDRESSES") | .usage' 2>/dev/null || echo "0")
    ip_limit=$(echo "$quotas" | jq -r '.quotas[] | select(.metric=="STATIC_ADDRESSES") | .limit' 2>/dev/null || echo "N/A")
    
    # Calculate percentages
    local cpu_pct="N/A" inst_pct="N/A" ip_pct="N/A"
    if [[ "$cpu_limit" != "N/A" ]] && [[ "$cpu_limit" != "0" ]]; then
        cpu_pct=$(awk "BEGIN {printf \"%.1f\", ($cpu_current/$cpu_limit)*100}")
    fi
    if [[ "$inst_limit" != "N/A" ]] && [[ "$inst_limit" != "0" ]]; then
        inst_pct=$(awk "BEGIN {printf \"%.1f\", ($inst_current/$inst_limit)*100}")
    fi
    if [[ "$ip_limit" != "N/A" ]] && [[ "$ip_limit" != "0" ]]; then
        ip_pct=$(awk "BEGIN {printf \"%.1f\", ($ip_current/$ip_limit)*100}")
    fi
    
    cat >> "$output_file" <<EOF
                <tr><td>vCPUs (Regional Total)</td><td>$cpu_current</td><td>$cpu_limit</td><td>$cpu_pct%</td></tr>
                <tr><td>Running Instances</td><td>$inst_current</td><td>$inst_limit</td><td>$inst_pct%</td></tr>
                <tr><td>Public IPs (Static)</td><td>$ip_current</td><td>$ip_limit</td><td>$ip_pct%</td></tr>
            </table>
EOF
    
    # List running instances
    if [[ "$inst_current" != "0" ]]; then
        {
            cat <<EOF
            <h4>Running Instances</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>Machine Type</th><th>Zone</th><th>Status</th><th>Labels</th></tr>
EOF
            gcloud compute instances list --filter="zone:$region*" --format=json 2>/dev/null | jq -r '.[] | 
                (.labels // {} | to_entries | map(select(.key | test("owner|creator|project"; "i")) | "\(.key)=\(.value)") | join(", ")) as $labels |
                "<tr><td>\(.name)</td><td>\(.machineType | split("/")[-1])</td><td>\(.zone | split("/")[-1])</td><td>\(.status)</td><td>\($labels)</td></tr>"'
            echo "            </table>"
        } >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}

# Parallel wrapper for GCP regions
collect_gcp_data_parallel() {
    local temp_dir="$1"
    local regions=("us-central1" "us-east1" "us-west1" "europe-west1" "europe-west2" "asia-southeast1")
    
    for region in "${regions[@]}"; do
        {
            collect_gcp_data "$region" "$temp_dir/gcp-$region.html"
        } &
    done
    wait
}

collect_hetzner_data() {
    local output_file="$1"
    
    if ! command -v hcloud &>/dev/null; then
        echo "<p class='warning'>Hetzner CLI not installed</p>" >> "$output_file"
        return
    fi
    
    if ! hcloud context list &>/dev/null 2>&1 && [[ -z "${HCLOUD_TOKEN:-}" ]]; then
        echo "<p class='warning'>Hetzner not configured</p>" >> "$output_file"
        return
    fi
    
    cat >> "$output_file" <<EOF
        <div class="region">
            <h3>Hetzner Cloud</h3>
            <h4>Resource Quotas</h4>
            <table class="quota-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
EOF
    
    local server_count=0
    local server_data
    server_data=$(hcloud server list -o json 2>/dev/null || echo "[]")
    server_count=$(echo "$server_data" | jq -r 'length' 2>/dev/null || echo "0")
    
    cat >> "$output_file" <<EOF
                <tr><td>Servers</td><td>$server_count</td><td>View in console</td><td>-</td></tr>
            </table>
            <p><small>Note: Limits available at <a href="https://console.hetzner.cloud/" target="_blank">console.hetzner.cloud</a> → Account → Limits</small></p>
EOF
    
    # List running servers
    if [[ "$server_count" -gt 0 ]]; then
        cat >> "$output_file" <<EOF
            <h4>Running Servers</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>Type</th><th>Location</th><th>Status</th></tr>
EOF
        echo "$server_data" | jq -r '.[] | "<tr><td>\(.name)</td><td>\(.server_type.name)</td><td>\(.datacenter.location.name)</td><td>\(.status)</td></tr>"' >> "$output_file" 2>/dev/null || true
        echo "            </table>" >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}

collect_digitalocean_data() {
    local output_file="$1"
    
    if ! command -v doctl &>/dev/null; then
        echo "<p class='warning'>DigitalOcean CLI not installed</p>" >> "$output_file"
        return
    fi
    
    cat >> "$output_file" <<EOF
        <div class="region">
            <h3>DigitalOcean</h3>
            <h4>Resource Quotas</h4>
            <table class="quota-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
EOF
    
    local droplet_limit droplet_count ip_limit volume_limit
    local account_data
    account_data=$(doctl account get --output json 2>/dev/null || echo "{}")
    droplet_limit=$(echo "$account_data" | jq -r '.droplet_limit // "N/A"')
    ip_limit=$(echo "$account_data" | jq -r '.floating_ip_limit // "N/A"')
    volume_limit=$(echo "$account_data" | jq -r '.volume_limit // "N/A"')
    
    local droplet_data
    droplet_data=$(doctl compute droplet list --output json 2>/dev/null || echo "[]")
    droplet_count=$(echo "$droplet_data" | jq -r 'length' 2>/dev/null || echo "0")
    
    local droplet_pct="N/A"
    if [[ "$droplet_limit" != "N/A" ]] && [[ "$droplet_limit" != "null" ]] && [[ "$droplet_limit" != "0" ]]; then
        droplet_pct=$(awk "BEGIN {printf \"%.1f\", ($droplet_count/$droplet_limit)*100}" 2>/dev/null || echo "N/A")
    fi
    
    cat >> "$output_file" <<EOF
                <tr><td>Droplets</td><td>$droplet_count</td><td>$droplet_limit</td><td>$droplet_pct%</td></tr>
                <tr><td>Floating IPs</td><td>-</td><td>$ip_limit</td><td>-</td></tr>
                <tr><td>Volumes</td><td>-</td><td>$volume_limit</td><td>-</td></tr>
            </table>
EOF
    
    # List running droplets
    if [[ "$droplet_count" -gt 0 ]]; then
        cat >> "$output_file" <<EOF
            <h4>Running Droplets</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>Size</th><th>Region</th><th>Status</th></tr>
EOF
        echo "$droplet_data" | jq -r '.[] | "<tr><td>\(.name)</td><td>\(.size.slug)</td><td>\(.region.slug)</td><td>\(.status)</td></tr>"' >> "$output_file" 2>/dev/null || true
        echo "            </table>" >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}

collect_libvirt_data() {
    local output_file="$1"
    
    if ! command -v virsh &>/dev/null; then
        echo "<p class='warning'>libvirt not installed</p>" >> "$output_file"
        return
    fi
    
    cat >> "$output_file" <<EOF
        <div class="region">
            <h3>libvirt (Local/KVM)</h3>
            <h4>Resource Quotas</h4>
            <table class="quota-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
EOF
    
    local vm_count running_count
    vm_count=$(virsh list --all 2>/dev/null | awk 'NR>2 && NF>0' | wc -l)
    running_count=$(virsh list --state-running 2>/dev/null | awk 'NR>2 && NF>0' | wc -l)
    
    cat >> "$output_file" <<EOF
                <tr><td>Total VMs</td><td>$vm_count</td><td>Host dependent</td><td>-</td></tr>
                <tr><td>Running VMs</td><td>$running_count</td><td>-</td><td>-</td></tr>
            </table>
            <p><small>Note: Limits depend on host resources (CPU, RAM, disk)</small></p>
EOF
    
    # List running VMs
    if [[ "$running_count" -gt 0 ]]; then
        {
            cat <<EOF
            <h4>Running VMs</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>State</th><th>ID</th></tr>
EOF
            virsh list --state-running 2>/dev/null | awk 'NR>2 && NF>0 {printf "                <tr><td>%s</td><td>%s</td><td>%s</td></tr>\n", $2, $3, $1}'
            echo "            </table>"
        } >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}

generate_html() {
    local output_file="$1"
    local provider_filter="${2:-}"
    local temp_dir="$3"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    
    generate_html_header > "$output_file"
    
    local providers=("aws" "azure" "gcp" "hetzner" "digitalocean" "libvirt")
    
    if [[ -n "$provider_filter" ]]; then
        providers=("$provider_filter")
    fi
    
    local provider_count=${#providers[@]}
    
    # Add header info section
    cat >> "$output_file" <<EOF
    <div class="header-info">
        <p><strong>Total Providers:</strong> $provider_count</p>
        <p><strong>Last Updated:</strong> $timestamp</p>
        <p><small>This page auto-refreshes every 60 seconds</small></p>
    </div>
EOF
    
    # Parallel data collection phase
    echo "Collecting data in parallel..." >&2
    local start_time
    start_time=$(date +%s)
    
    for prov in "${providers[@]}"; do
        case "$prov" in
            aws)
                if command -v aws &>/dev/null; then
                    collect_aws_data_parallel "$temp_dir" &
                fi
                ;;
            azure)
                if command -v az &>/dev/null; then
                    collect_azure_data_parallel "$temp_dir" &
                fi
                ;;
            gcp)
                if command -v gcloud &>/dev/null; then
                    collect_gcp_data_parallel "$temp_dir" &
                fi
                ;;
        esac
    done
    wait
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "Data collection completed in ${duration}s" >&2
    
    # Generate HTML from collected data
    echo "Generating report..." >&2
    local gen_start_time
    gen_start_time=$(date +%s)
    
    # Generate HTML from collected data
    for prov in "${providers[@]}"; do
        # Extract summary data from already-collected files
        local summary=""
        local ip_summary=""
        case "$prov" in
            aws)
                if command -v aws &>/dev/null; then
                    local total_instances=0
                    local total_ips=0
                    for region in us-east-1 us-east-2 us-west-1 us-west-2 eu-west-1 eu-west-2 eu-central-1 ap-southeast-1 ap-northeast-1; do
                        if [[ -f "$temp_dir/aws-$region.html" ]]; then
                            local inst=$(grep -o "Running Instances</td><td>[0-9]*" "$temp_dir/aws-$region.html" | grep -o "[0-9]*$" || echo "0")
                            local ips=$(grep -o "Public IPs (Elastic)</td><td>[0-9]*" "$temp_dir/aws-$region.html" | grep -o "[0-9]*$" || echo "0")
                            total_instances=$((total_instances + inst))
                            total_ips=$((total_ips + ips))
                        fi
                    done
                    summary="$total_instances instances"
                    ip_summary="$total_ips IPs"
                else
                    summary="CLI not installed"
                fi
                ;;
            azure)
                if command -v az &>/dev/null; then
                    local vm_count=0
                    local ip_count=0
                    for location in eastus eastus2 westus westus2 westeurope northeurope; do
                        if [[ -f "$temp_dir/azure-$location.html" ]]; then
                            local vms=$(grep -o "Running Instances</td><td>[0-9]*" "$temp_dir/azure-$location.html" | grep -o "[0-9]*$" || echo "0")
                            local ips=$(grep -o "Public IPs</td><td>[0-9]*" "$temp_dir/azure-$location.html" | grep -o "[0-9]*$" || echo "0")
                            vm_count=$((vm_count + vms))
                            ip_count=$((ip_count + ips))
                        fi
                    done
                    summary="$vm_count VMs"
                    ip_summary="$ip_count IPs"
                else
                    summary="CLI not installed"
                fi
                ;;
            gcp)
                if command -v gcloud &>/dev/null; then
                    local inst_count=0
                    local ip_count=0
                    for region in us-central1 us-east1 us-west1 europe-west1 europe-west2 asia-southeast1; do
                        if [[ -f "$temp_dir/gcp-$region.html" ]]; then
                            local insts=$(grep -o "Running Instances</td><td>[0-9]*" "$temp_dir/gcp-$region.html" | grep -o "[0-9]*$" || echo "0")
                            local ips=$(grep -o "Public IPs (Static)</td><td>[0-9]*" "$temp_dir/gcp-$region.html" | grep -o "[0-9]*$" || echo "0")
                            inst_count=$((inst_count + insts))
                            ip_count=$((ip_count + ips))
                        fi
                    done
                    summary="$inst_count instances"
                    ip_summary="$ip_count IPs"
                else
                    summary="CLI not installed"
                fi
                ;;
            hetzner)
                if command -v hcloud &>/dev/null && (hcloud context list &>/dev/null 2>&1 || [[ -n "${HCLOUD_TOKEN:-}" ]]); then
                    local server_data=$(hcloud server list -o json 2>/dev/null || echo "[]")
                    local server_count=$(echo "$server_data" | jq -r 'length' 2>/dev/null || echo "0")
                    summary="$server_count servers"
                else
                    summary="Not configured"
                fi
                ;;
            digitalocean)
                if command -v doctl &>/dev/null; then
                    local droplet_data=$(doctl compute droplet list --output json 2>/dev/null || echo "[]")
                    local droplet_count=$(echo "$droplet_data" | jq -r 'length' 2>/dev/null || echo "0")
                    local ip_count=$(doctl compute floating-ip list --output json 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0")
                    summary="$droplet_count droplets"
                    ip_summary="$ip_count IPs"
                else
                    summary="CLI not installed"
                fi
                ;;
            libvirt)
                if command -v virsh &>/dev/null; then
                    local vm_count=$(virsh list --all 2>/dev/null | awk 'NR>2 && NF>0' | wc -l)
                    summary="$vm_count VMs"
                else
                    summary="Not installed"
                fi
                ;;
        esac
        
        # Determine badge class
        local badge_class="badge"
        if [[ "$summary" =~ ^[1-9] ]]; then
            badge_class="badge active"
        fi
        
        local ip_badge_class="badge"
        if [[ "$ip_summary" =~ ^[1-9] ]]; then
            ip_badge_class="badge active"
        fi
        
        {
            echo "    <div class=\"provider\">"
            echo "        <div class=\"provider-header collapsed\" id=\"${prov}-header\" onclick=\"toggleProvider('${prov}')\">"
            echo "            <div>"
            echo "                <h2>${prov^^}</h2>"
            echo "                <span class=\"provider-summary\"><span class=\"$badge_class\">$summary</span>"
            if [[ -n "$ip_summary" ]]; then
                echo "<span class=\"$ip_badge_class\">$ip_summary</span>"
            fi
            echo "</span>"
            echo "            </div>"
            echo "            <div class=\"toggle-icon\" id=\"${prov}-icon\">▶</div>"
            echo "        </div>"
            echo "        <div class=\"provider-content collapsed\" id=\"${prov}-content\">"
        } >> "$output_file"
        
        case "$prov" in
            aws)
                for region in us-east-1 us-east-2 us-west-1 us-west-2 eu-west-1 eu-west-2 eu-central-1 ap-southeast-1 ap-northeast-1; do
                    if [[ -f "$temp_dir/aws-$region.html" ]]; then
                        cat "$temp_dir/aws-$region.html" >> "$output_file"
                    fi
                done
                ;;
            azure)
                for location in eastus eastus2 westus westus2 westeurope northeurope; do
                    if [[ -f "$temp_dir/azure-$location.html" ]]; then
                        cat "$temp_dir/azure-$location.html" >> "$output_file"
                    fi
                done
                ;;
            gcp)
                for region in us-central1 us-east1 us-west1 europe-west1 europe-west2 asia-southeast1; do
                    if [[ -f "$temp_dir/gcp-$region.html" ]]; then
                        cat "$temp_dir/gcp-$region.html" >> "$output_file"
                    fi
                done
                ;;
            hetzner)
                collect_hetzner_data "$output_file"
                ;;
            digitalocean)
                collect_digitalocean_data "$output_file"
                ;;
            libvirt)
                collect_libvirt_data "$output_file"
                ;;
        esac
        
        {
            echo "        </div>"
            echo "    </div>"
        } >> "$output_file"
    done
    
    generate_html_footer >> "$output_file"
    
    local gen_end_time
    gen_end_time=$(date +%s)
    local gen_duration=$((gen_end_time - gen_start_time))
    echo "Report generated in ${gen_duration}s" >&2
}

main() {
    local output_file="limits-report.html"
    local provider=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output) output_file="$2"; shift 2 ;;
            --provider) provider="$2"; shift 2 ;;
            --help) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done
    
    local output_dir
    local output_name
    output_dir="$(dirname "$output_file")"
    output_name="$(basename "$output_file")"
    local temp_file="${output_dir}/.tmp-${output_name}"
    
    # Create temp directory for parallel collection
    TEMP_DIR=$(mktemp -d)
    trap cleanup_temp EXIT INT TERM
    
    echo "Generating HTML report..."
    generate_html "$temp_file" "$provider" "$TEMP_DIR"
    mv "$temp_file" "$output_file"
    echo "Saved to: $output_file"
}

main "$@"

