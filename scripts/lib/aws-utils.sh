#!/usr/bin/env bash
# AWS utility functions for resource management and reporting

# List AWS EC2 instances
list_aws_instances() {
    local region="$1"
    local prefix_filter="${2:-}"
    
    local filter_args=()
    if [[ -n "$prefix_filter" ]]; then
        filter_args=(--filters "Name=tag:Name,Values=*${prefix_filter}*")
    fi
    
    aws ec2 describe-instances --region "$region" "${filter_args[@]}" \
        --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,InstanceId:InstanceId,State:State.Name,Type:InstanceType}" \
        --output json 2>/dev/null || echo "[]"
}

# List AWS EBS volumes
list_aws_volumes() {
    local region="$1"
    local prefix_filter="${2:-}"
    
    local filter_args=()
    if [[ -n "$prefix_filter" ]]; then
        filter_args=(--filters "Name=tag:Name,Values=*${prefix_filter}*")
    fi
    
    aws ec2 describe-volumes --region "$region" "${filter_args[@]}" \
        --query "Volumes[].{Name:Tags[?Key=='Name']|[0].Value,VolumeId:VolumeId,State:State,Size:Size}" \
        --output json 2>/dev/null || echo "[]"
}

# Terminate AWS instance
terminate_aws_instance() {
    local region="$1"
    local instance_id="$2"
    local instance_name="$3"
    
    echo "    Terminating: $instance_name"
    if aws ec2 terminate-instances --region "$region" --instance-ids "$instance_id" >/dev/null 2>&1; then
        echo "    ✓ Terminated: $instance_name"
    else
        echo "    ✗ Failed to terminate: $instance_name"
    fi
}

# Delete AWS volume
delete_aws_volume() {
    local region="$1"
    local volume_id="$2"
    local volume_name="$3"
    
    echo "    Deleting: $volume_name"
    if aws ec2 delete-volume --region "$region" --volume-id "$volume_id" >/dev/null 2>&1; then
        echo "    ✓ Deleted: $volume_name"
    else
        echo "    ✗ Failed to delete: $volume_name"
    fi
}

# Generate AWS HTML report for a region
generate_aws_html_report() {
    local region="$1"
    local output_file="$2"
    
    # Get instances and volumes
    local instances_json
    instances_json=$(list_aws_instances "$region")
    local running_count
    running_count=$(echo "$instances_json" | jq '[.[] | select(.State == "running")] | length' 2>/dev/null || echo "0")
    
    # Get limits (simplified)
    local instance_limit="20"  # Default limit, could be queried from service quotas
    local usage_pct=0
    if [[ "$instance_limit" -gt 0 ]]; then
        usage_pct=$(( (running_count * 100) / instance_limit ))
    fi
    
    # Generate HTML
    cat > "$output_file" <<EOF
        <div class="provider-section">
            <h3>AWS - $region</h3>
            <table class="limits-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
                <tr><td>Running Instances</td><td>$running_count</td><td>$instance_limit</td><td>$usage_pct%</td></tr>
            </table>
EOF
    
    # List running instances
    if [[ "$running_count" -gt 0 ]]; then
        cat >> "$output_file" <<EOF
            <h4>Running Instances</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>Instance ID</th><th>Type</th><th>State</th></tr>
EOF
        echo "$instances_json" | jq -r '.[] | select(.State == "running") | "<tr><td>\(.Name // "N/A")</td><td>\(.InstanceId)</td><td>\(.Type)</td><td>\(.State)</td></tr>"' >> "$output_file" 2>/dev/null || true
        echo "            </table>" >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}
