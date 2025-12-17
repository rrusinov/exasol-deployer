#!/usr/bin/env bash
# GCP utility functions for resource management and reporting

# Get current GCP project
get_gcp_project() {
    gcloud config get-value project 2>/dev/null || echo ""
}

# List GCP instances in a region
list_gcp_instances() {
    local region="$1"
    local prefix_filter="${2:-}"
    
    local filter_args=""
    if [[ -n "$prefix_filter" ]]; then
        filter_args="--filter=name~${prefix_filter}"
    fi
    
    gcloud compute instances list --regions="$region" $filter_args \
        --format="json(name,status,machineType.scope(machineTypes),zone.scope(zones))" 2>/dev/null || echo "[]"
}

# Delete GCP instance
delete_gcp_instance() {
    local zone="$1"
    local instance_name="$2"
    
    echo "    Deleting: $instance_name"
    if gcloud compute instances delete "$instance_name" --zone="$zone" --quiet >/dev/null 2>&1; then
        echo "    ✓ Deleted: $instance_name"
    else
        echo "    ✗ Failed to delete: $instance_name"
    fi
}

# Generate GCP HTML report for a region
generate_gcp_html_report() {
    local region="$1"
    local output_file="$2"
    
    # Get instances
    local instances_json
    instances_json=$(list_gcp_instances "$region")
    local instance_count
    instance_count=$(echo "$instances_json" | jq '. | length' 2>/dev/null || echo "0")
    local running_count
    running_count=$(echo "$instances_json" | jq '[.[] | select(.status == "RUNNING")] | length' 2>/dev/null || echo "0")
    
    # Generate HTML
    cat > "$output_file" <<EOF
        <div class="provider-section">
            <h3>GCP - $region</h3>
            <table class="limits-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
                <tr><td>Running Instances</td><td>$running_count</td><td>-</td><td>-</td></tr>
                <tr><td>Total Instances</td><td>$instance_count</td><td>-</td><td>-</td></tr>
            </table>
EOF
    
    # List running instances
    if [[ "$running_count" -gt 0 ]]; then
        cat >> "$output_file" <<EOF
            <h4>Running Instances</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>Machine Type</th><th>Zone</th><th>Status</th></tr>
EOF
        echo "$instances_json" | jq -r '.[] | select(.status == "RUNNING") | "<tr><td>\(.name)</td><td>\(.machineType)</td><td>\(.zone)</td><td>\(.status)</td></tr>"' >> "$output_file" 2>/dev/null || true
        echo "            </table>" >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}
