#!/usr/bin/env bash
# Azure utility functions for resource management and reporting

# List Azure resource groups with prefix filter
list_azure_resource_groups() {
    local prefix_filter="${1:-}"
    
    if [[ -n "$prefix_filter" ]]; then
        az group list --query "[?contains(name, '$prefix_filter')].name" -o tsv 2>/dev/null || echo ""
    else
        az group list --query "[].name" -o tsv 2>/dev/null || echo ""
    fi
}

# List Azure VMs in a location
list_azure_vms() {
    local location="$1"
    local prefix_filter="${2:-}"
    
    local query="[?location=='$location']"
    if [[ -n "$prefix_filter" ]]; then
        query="[?location=='$location' && contains(name, '$prefix_filter')]"
    fi
    
    az vm list --query "$query.{name:name,state:powerState,size:hardwareProfile.vmSize,resourceGroup:resourceGroup}" \
        --output json 2>/dev/null || echo "[]"
}

# Delete Azure resource group
delete_azure_resource_group() {
    local rg_name="$1"
    
    echo "    Deleting resource group: $rg_name"
    if az group delete --name "$rg_name" --yes --no-wait 2>/dev/null; then
        echo "    ✓ Deletion initiated: $rg_name"
    else
        echo "    ✗ Failed to delete: $rg_name"
    fi
}

# Generate Azure HTML report for a location
generate_azure_html_report() {
    local location="$1"
    local output_file="$2"
    
    # Get VMs
    local vms_json
    vms_json=$(list_azure_vms "$location")
    local vm_count
    vm_count=$(echo "$vms_json" | jq '. | length' 2>/dev/null || echo "0")
    
    # Generate HTML
    cat > "$output_file" <<EOF
        <div class="provider-section">
            <h3>Azure - $location</h3>
            <table class="limits-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
                <tr><td>Virtual Machines</td><td>$vm_count</td><td>-</td><td>-</td></tr>
            </table>
EOF
    
    # List VMs
    if [[ "$vm_count" -gt 0 ]]; then
        cat >> "$output_file" <<EOF
            <h4>Virtual Machines</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>Size</th><th>State</th><th>Resource Group</th></tr>
EOF
        echo "$vms_json" | jq -r '.[] | "<tr><td>\(.name)</td><td>\(.size)</td><td>\(.state // "Unknown")</td><td>\(.resourceGroup)</td></tr>"' >> "$output_file" 2>/dev/null || true
        echo "            </table>" >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}
