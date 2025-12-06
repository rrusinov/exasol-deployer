#!/usr/bin/env bash
# Generate HTML report of cloud resource limits

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    <title>Cloud Resource Limits Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #333; }
        .provider { background: white; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .provider-header { background: #4CAF50; color: white; padding: 15px; cursor: pointer; border-radius: 8px 8px 0 0; user-select: none; }
        .provider-header:hover { background: #45a049; }
        .provider-header::before { content: '▼ '; }
        .provider-header.collapsed::before { content: '▶ '; }
        .provider-header h2 { display: inline-block; margin: 0; }
        .provider-summary { display: inline-block; margin-left: 20px; font-size: 0.9em; opacity: 0.9; }
        .provider-summary .badge { background: rgba(255,255,255,0.2); padding: 4px 8px; border-radius: 4px; margin: 0 4px; }
        .provider-summary .badge.active { background: rgba(255,255,255,0.3); font-weight: bold; }
        .provider-content { padding: 15px; max-height: 5000px; overflow: hidden; transition: max-height 0.3s ease; }
        .provider-content.collapsed { max-height: 0; padding: 0 15px; }
        .region { margin: 15px 0; padding: 15px; background: #f9f9f9; border-left: 4px solid #2196F3; }
        .region h3 { margin-top: 0; color: #2196F3; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; background: white; }
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
        .timestamp { color: #999; font-size: 0.9em; text-align: right; }
        .summary { background: #e3f2fd; padding: 10px; margin: 10px 0; border-radius: 4px; }
    </style>
    <script>
        function toggleProvider(id) {
            const header = document.getElementById(id + '-header');
            const content = document.getElementById(id + '-content');
            header.classList.toggle('collapsed');
            content.classList.toggle('collapsed');
        }
    </script>
</head>
<body>
    <h1>Cloud Resource Limits Report</h1>
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
    # shellcheck disable=SC2016  # Backticks are part of JMESPath query syntax, not shell expansion
    instance_count=$(aws ec2 describe-instances --region "$region" --query 'length(Reservations[].Instances[?State.Name==`running`])' --output text 2>/dev/null || echo "0")
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
    
    # Get public IPs
    ip_current=$(az network public-ip list --query 'length(@)' --output tsv 2>/dev/null || echo "0")
    ip_limit=$(az network list-usages --location "$location" --output json 2>/dev/null | jq -r '.[] | select(.name.localizedValue=="Public IP Addresses") | .limit' 2>/dev/null)
    [[ -z "$ip_limit" ]] && ip_limit="N/A"
    
    # Get VM count
    local vm_count
    vm_count=$(az vm list --query 'length(@)' --output tsv 2>/dev/null || echo "0")
    
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
    
    # List running VMs
    if [[ "$vm_count" -gt 0 ]]; then
        {
            cat <<EOF
            <h4>Running Virtual Machines</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>Size</th><th>Location</th><th>State</th><th>Tags</th></tr>
EOF
            az vm list --output json 2>/dev/null | jq -r '.[] | 
                (.tags // {} | to_entries | map(select(.key | test("owner|creator|project"; "i")) | "\(.key)=\(.value)") | join(", ")) as $tags |
                "<tr><td>\(.name)</td><td>\(.hardwareProfile.vmSize)</td><td>\(.location)</td><td>\(.provisioningState)</td><td>\($tags)</td></tr>"'
            echo "            </table>"
        } >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
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
    local timestamp
    timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    
    generate_html_header > "$output_file"
    echo "    <div class=\"timestamp\">Generated: $timestamp</div>" >> "$output_file"
    
    local providers=("aws" "azure" "gcp" "hetzner" "digitalocean" "libvirt")
    
    if [[ -n "$provider_filter" ]]; then
        providers=("$provider_filter")
    fi
    
    for prov in "${providers[@]}"; do
        # Collect summary data first
        local summary=""
        case "$prov" in
            aws)
                if command -v aws &>/dev/null; then
                    local total_instances=0
                    for region in us-east-1 us-east-2 us-west-1 us-west-2 eu-west-1 eu-west-2 eu-central-1 ap-southeast-1 ap-northeast-1; do
                        # shellcheck disable=SC2016  # Backticks are part of JMESPath query syntax
                        local inst=$(aws ec2 describe-instances --region "$region" --query 'length(Reservations[].Instances[?State.Name==`running`])' --output text 2>/dev/null || echo "0")
                        total_instances=$((total_instances + inst))
                    done
                    summary="$total_instances instances"
                else
                    summary="CLI not installed"
                fi
                ;;
            azure)
                if command -v az &>/dev/null; then
                    local vm_count=$(az vm list --query 'length(@)' --output tsv 2>/dev/null || echo "0")
                    summary="$vm_count VMs"
                else
                    summary="CLI not installed"
                fi
                ;;
            gcp)
                if command -v gcloud &>/dev/null; then
                    local project=$(gcloud config get-value project 2>/dev/null || echo "")
                    if [[ -n "$project" ]]; then
                        local inst_count=$(gcloud compute instances list --format="value(name)" 2>/dev/null | wc -l)
                        summary="$inst_count instances"
                    else
                        summary="Not configured"
                    fi
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
                    summary="$droplet_count droplets"
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
        
        {
            echo "    <div class=\"provider\">"
            echo "        <div class=\"provider-header collapsed\" id=\"${prov}-header\" onclick=\"toggleProvider('${prov}')\">"
            echo "            <h2>${prov^^}</h2>"
            echo "            <span class=\"provider-summary\"><span class=\"$badge_class\">$summary</span></span>"
            echo "        </div>"
            echo "        <div class=\"provider-content collapsed\" id=\"${prov}-content\">"
        } >> "$output_file"
        
        case "$prov" in
            aws)
                for region in us-east-1 us-east-2 us-west-1 us-west-2 eu-west-1 eu-west-2 eu-central-1 ap-southeast-1 ap-northeast-1; do
                    collect_aws_data "$region" "$output_file"
                done
                ;;
            azure)
                for location in eastus eastus2 westus westus2 westeurope northeurope; do
                    collect_azure_data "$location" "$output_file"
                done
                ;;
            gcp)
                for region in us-central1 us-east1 us-west1 europe-west1 europe-west2 asia-southeast1; do
                    collect_gcp_data "$region" "$output_file"
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
    
    echo "Generating HTML report..."
    generate_html "$output_file" "$provider"
    echo "Report generated: $output_file"
}

main "$@"

