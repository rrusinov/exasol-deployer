#!/usr/bin/env bash
# Hetzner utility functions for resource management and reporting

# List Hetzner servers
list_hetzner_servers() {
    local prefix_filter="${1:-}"
    
    local selector=""
    if [[ -n "$prefix_filter" ]]; then
        selector="name~$prefix_filter"
    fi
    
    hcloud server list -o json ${selector:+--selector "$selector"} 2>/dev/null || echo "[]"
}

# List Hetzner volumes
list_hetzner_volumes() {
    local prefix_filter="${1:-}"
    
    local selector=""
    if [[ -n "$prefix_filter" ]]; then
        selector="name~$prefix_filter"
    fi
    
    hcloud volume list -o json ${selector:+--selector "$selector"} 2>/dev/null || echo "[]"
}

# Delete Hetzner server
delete_hetzner_server() {
    local server_name="$1"
    
    echo "    Deleting server: $server_name"
    if hcloud server delete "$server_name" >/dev/null 2>&1; then
        echo "    ✓ Deleted: $server_name"
    else
        echo "    ✗ Failed to delete: $server_name"
    fi
}

# Delete Hetzner volume
delete_hetzner_volume() {
    local volume_name="$1"
    
    echo "    Deleting volume: $volume_name"
    if hcloud volume delete "$volume_name" >/dev/null 2>&1; then
        echo "    ✓ Deleted: $volume_name"
    else
        echo "    ✗ Failed to delete: $volume_name"
    fi
}

# Generate Hetzner cleanup summary
generate_hetzner_cleanup_summary() {
    local prefix_filter="${1:-}"
    
    echo "=== HETZNER RESOURCES ==="
    echo ""
    
    # Get servers
    local servers_json
    servers_json=$(list_hetzner_servers "$prefix_filter")
    
    echo "Servers:"
    if [[ "$(echo "$servers_json" | jq '. | length' 2>/dev/null || echo "0")" -gt 0 ]]; then
        echo "$servers_json" | jq -r '.[] | "  \(.status | ascii_upcase): \(.name) (ID: \(.id), Type: \(.server_type.name))"' 2>/dev/null || echo "  (parse error)"
    else
        echo "  (none)"
    fi
    echo ""
    
    # Get volumes
    local volumes_json
    volumes_json=$(list_hetzner_volumes "$prefix_filter")
    
    echo "Volumes:"
    if [[ "$(echo "$volumes_json" | jq '. | length' 2>/dev/null || echo "0")" -gt 0 ]]; then
        echo "$volumes_json" | jq -r '.[] | "  \(.status | ascii_upcase): \(.name) (ID: \(.id), Size: \(.size)GB)"' 2>/dev/null || echo "  (parse error)"
    else
        echo "  (none)"
    fi
    
    # Save data for cleanup
    echo "$servers_json" > /tmp/hetzner_servers.json
    echo "$volumes_json" > /tmp/hetzner_volumes.json
}

# Generate Hetzner HTML report
generate_hetzner_html_report() {
    local output_file="$1"
    
    # Get servers and volumes
    local servers_json
    servers_json=$(list_hetzner_servers)
    local server_count
    server_count=$(echo "$servers_json" | jq '. | length' 2>/dev/null || echo "0")
    
    local volumes_json
    volumes_json=$(list_hetzner_volumes)
    local volume_count
    volume_count=$(echo "$volumes_json" | jq '. | length' 2>/dev/null || echo "0")
    
    # Generate HTML
    cat > "$output_file" <<EOF
        <div class="provider-section">
            <h3>Hetzner Cloud</h3>
            <table class="limits-table">
                <tr><th>Resource</th><th>Current</th><th>Limit</th><th>Usage %</th></tr>
                <tr><td>Servers</td><td>$server_count</td><td>-</td><td>-</td></tr>
                <tr><td>Volumes</td><td>$volume_count</td><td>-</td><td>-</td></tr>
            </table>
EOF
    
    # List servers
    if [[ "$server_count" -gt 0 ]]; then
        cat >> "$output_file" <<EOF
            <h4>Servers</h4>
            <table class="instances-table">
                <tr><th>Name</th><th>Type</th><th>Location</th><th>Status</th></tr>
EOF
        echo "$servers_json" | jq -r '.[] | "<tr><td>\(.name)</td><td>\(.server_type.name)</td><td>\(.datacenter.location.name)</td><td>\(.status)</td></tr>"' >> "$output_file" 2>/dev/null || true
        echo "            </table>" >> "$output_file"
    fi
    
    echo "        </div>" >> "$output_file"
}
