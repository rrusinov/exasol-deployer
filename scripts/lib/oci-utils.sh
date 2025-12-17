#!/usr/bin/env bash
# OCI utility functions for resource management and reporting

# Get compartment OCID from config file or fallback to tenancy
get_oci_compartment_ocid() {
    local compartment_ocid
    
    # First try to read compartment from ~/.oci/config
    if [[ -f ~/.oci/config ]]; then
        compartment_ocid=$(grep "^compartment=" ~/.oci/config | cut -d'=' -f2 | tr -d ' ' | head -1)
    fi
    
    # If not found in config, try to get tenancy OCID as fallback
    if [[ -z "$compartment_ocid" ]]; then
        compartment_ocid=$(oci iam tenancy get --query "data.id" --raw-output 2>/dev/null || echo "")
    fi
    
    echo "$compartment_ocid"
}

# Get current OCI region
get_oci_region() {
    oci iam region-subscription list --query "data[?\"is-home-region\"].\"region-name\" | [0]" --raw-output 2>/dev/null || echo "unknown"
}

# List OCI compute instances
list_oci_instances() {
    local compartment_ocid="$1"
    local prefix_filter="${2:-}"
    
    local query="data[]"
    if [[ -n "$prefix_filter" ]]; then
        query="data[?contains(\"display-name\", '$prefix_filter')]"
    fi
    
    oci compute instance list \
        --compartment-id "$compartment_ocid" \
        --query "$query.{name:\"display-name\",id:id,state:\"lifecycle-state\",shape:shape}" \
        --output json 2>/dev/null || echo "[]"
}

# List OCI block volumes
list_oci_volumes() {
    local compartment_ocid="$1"
    local prefix_filter="${2:-}"
    
    local query="data[]"
    if [[ -n "$prefix_filter" ]]; then
        query="data[?contains(\"display-name\", '$prefix_filter')]"
    fi
    
    oci bv volume list \
        --compartment-id "$compartment_ocid" \
        --query "$query.{name:\"display-name\",id:id,state:\"lifecycle-state\",size:\"size-in-gbs\"}" \
        --output json 2>/dev/null || echo "[]"
}

# Terminate OCI instance
terminate_oci_instance() {
    local instance_id="$1"
    local instance_name="$2"
    
    echo "    Terminating: $instance_name"
    if oci compute instance terminate --instance-id "$instance_id" --force --wait-for-state TERMINATED 2>/dev/null; then
        echo "    ✓ Terminated: $instance_name"
    else
        echo "    ✗ Failed to terminate: $instance_name"
    fi
}

# Delete OCI volume
delete_oci_volume() {
    local volume_id="$1"
    local volume_name="$2"
    
    echo "    Deleting: $volume_name"
    if oci bv volume delete --volume-id "$volume_id" --force --wait-for-state TERMINATED 2>/dev/null; then
        echo "    ✓ Deleted: $volume_name"
    else
        echo "    ✗ Failed to delete: $volume_name"
    fi
}

# Generate OCI resource summary for cleanup
generate_oci_cleanup_summary() {
    local compartment_ocid="$1"
    local prefix_filter="${2:-}"
    
    echo "=== OCI RESOURCES ==="
    echo ""
    
    # Get instances
    local instances_json
    instances_json=$(list_oci_instances "$compartment_ocid" "$prefix_filter")
    local instances
    instances=$(echo "$instances_json" | jq -r '.[] | "\(.state): \(.name) (\(.id))"' 2>/dev/null || echo "")
    
    echo "Compute Instances:"
    if [[ -n "$instances" ]]; then
        echo "$instances" | sed 's/^/  /'
    else
        echo "  (none)"
    fi
    echo ""
    
    # Get volumes
    local volumes_json
    volumes_json=$(list_oci_volumes "$compartment_ocid" "$prefix_filter")
    local volumes
    volumes=$(echo "$volumes_json" | jq -r '.[] | "\(.state): \(.name) (\(.id))"' 2>/dev/null || echo "")
    
    echo "Block Volumes:"
    if [[ -n "$volumes" ]]; then
        echo "$volumes" | sed 's/^/  /'
    else
        echo "  (none)"
    fi
    
    # Return data for cleanup actions
    echo "$instances_json" > /tmp/oci_instances.json
    echo "$volumes_json" > /tmp/oci_volumes.json
}

# Generate OCI HTML report section
generate_oci_html_report() {
    local compartment_ocid="$1"
    local region="$2"
    local output_file="$3"
    
    # Get instances and volumes
    local instances_json
    instances_json=$(list_oci_instances "$compartment_ocid")
    local instance_count
    instance_count=$(echo "$instances_json" | jq '. | length' 2>/dev/null || echo "0")
    
    local volumes_json
    volumes_json=$(list_oci_volumes "$compartment_ocid")
    local volume_count
    volume_count=$(echo "$volumes_json" | jq '. | length' 2>/dev/null || echo "0")
    
    # Generate HTML
    cat > "$output_file" <<EOF
        <div class="provider-section">
            <h3>OCI - $region</h3>
            <table class="limits-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
                <tr><td>Compute Instances</td><td>$instance_count</td><td>-</td><td>-</td></tr>
                <tr><td>Block Volumes</td><td>$volume_count</td><td>-</td><td>-</td></tr>
            </table>
EOF
    
    # List running instances
    if [[ "$instance_count" -gt 0 ]]; then
        cat >> "$output_file" <<EOF
            <h4>Running Instances</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>Shape</th><th>State</th></tr>
EOF
        echo "$instances_json" | jq -r '.[] | "<tr><td>\(.name)</td><td>\(.shape)</td><td>\(.state)</td></tr>"' >> "$output_file" 2>/dev/null || true
        echo "            </table>" >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}
