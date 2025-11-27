#!/usr/bin/env bash
# Internal health check functions
# This file contains the core health check logic extracted for reusability

# Determine deployment status from health check results
# This function contains the core logic for determining what status the deployment should be in
# based on health check results. It's called both during wait-for loops and after full health checks.
#
# Parameters:
#   $1 - deploy_dir
#   $2 - ssh_passed (number of nodes reachable via SSH)
#   $3 - ssh_failed (number of nodes unreachable via SSH)
#   $4 - cluster_status (cluster_stage_d, cluster_not_stage_d, or unknown)
#   $5 - overall_issues (0 if healthy, >0 if issues detected)
#
# Returns: "database_ready", "database_connection_failed", "stopped", or current status if no change
health_determine_status() {
    local deploy_dir="$1"
    local ssh_passed="$2"
    local ssh_failed="$3"
    local cluster_status="$4"
    local overall_issues="$5"

    local current_status
    current_status=$(state_get_status "$deploy_dir" 2>/dev/null || echo "unknown")

    local cluster_size
    cluster_size=$(state_read "$deploy_dir" "cluster_size" 2>/dev/null)
    cluster_size=${cluster_size:-$ssh_failed}

    # Determine if cluster is ready (all checks passed and in stage d)
    local cluster_ready="false"
    [[ "$overall_issues" -eq 0 && "$cluster_status" == "cluster_stage_d" ]] && cluster_ready="true"

    # Apply status transition rules (same logic as in full health check)
    local new_status="$current_status"

    if [[ "$ssh_passed" -eq 0 && "$ssh_failed" -eq "$cluster_size" && "$cluster_size" -gt 0 ]]; then
        # All nodes unreachable via SSH -> treat as stopped regardless of previous status
        new_status="stopped"
    elif [[ "$current_status" == "database_connection_failed" && "$ssh_passed" -eq 0 && "$ssh_failed" -eq "$cluster_size" && "$cluster_size" -gt 0 ]]; then
        # If database connection failed and nothing is reachable, mark as stopped
        new_status="stopped"
    elif [[ "$cluster_ready" == "true" ]]; then
        # Cluster is healthy - transition to database_ready from failure/stopped/started states
        case "$current_status" in
            deployment_failed|database_connection_failed|start_failed|stop_failed|destroy_failed|stopped|started)
                new_status="database_ready"
                ;;
        esac
    elif [[ "$current_status" == "database_ready" && "$cluster_status" != "cluster_stage_d" ]]; then
        # Database claims ready but cluster not in stage d
        new_status="database_connection_failed"
    elif [[ "$current_status" == "stopped" && "$ssh_passed" -gt 0 ]]; then
        # Claims stopped but SSH reachable
        new_status="stop_failed"
    elif [[ "$current_status" == "started" ]]; then
        # In started state - determine actual status
        if [[ "$ssh_passed" -eq 0 && "$ssh_failed" -gt 0 ]]; then
            # All nodes unreachable - still waiting for power on
            new_status="started"
        elif [[ "$cluster_status" == "cluster_stage_d" && "$overall_issues" -eq 0 ]]; then
            # Cluster is ready
            new_status="database_ready"
        elif [[ "$ssh_passed" -gt 0 ]]; then
            # Some nodes reachable but cluster not ready yet
            new_status="started"
        fi
    fi

    echo "$new_status"
}

# Internal function to run health checks
# This is the core health check logic used by both wait-for loop and final check
#
# Parameters:
#   $1 - deploy_dir
#   $2 - verbosity (normal|verbose|quiet)
#   $3 - output_format (text|json)
#   $4 - do_update_metadata (true|false)
#   $5 - cloud_provider
#   $6 - update_status (true|false) - optional, defaults to true
#
# Returns via global variables (because bash):
#   Sets: overall_issues, ssh_passed, ssh_failed, cluster_status, cluster_ready
#   and many other metrics
health_run_internal_checks() {
    local deploy_dir="$1"
    local verbosity="$2"
    local output_format="$3"
    local do_update_metadata="$4"
    local cloud_provider="$5"
    local update_status="${6:-true}"

        local inventory_file="$deploy_dir/inventory.ini"
        local ssh_config_file="$deploy_dir/ssh_config"

        if [[ ! -f "$inventory_file" ]]; then
            lock_remove "$deploy_dir"
            die "Missing inventory.ini in $deploy_dir"
        fi

        if [[ ! -f "$ssh_config_file" ]]; then
            lock_remove "$deploy_dir"
            die "Missing ssh_config in $deploy_dir"
        fi

        health_require_tool "ssh"

        local -a host_entries=()

        # Parse inventory file using awk to extract host entries (portable across BSD/GNU awk)
        if [[ -f "$inventory_file" ]]; then
            while IFS= read -r entry; do
                [[ -n "$entry" ]] && host_entries+=("$entry")
            done < <(awk '
            BEGIN { section = "" }
            {
                # Skip empty lines and comments
                if (NF == 0 || $0 ~ /^[[:space:]]*#/) {
                    next
                }

                # Check for section headers
                if ($0 ~ /^\[/) {
                    section = $0
                    gsub(/^[[:space:]]*\[/, "", section)
                    gsub(/\].*$/, "", section)
                    next
                }

                # Only process lines in the exasol_nodes section
                if (section != "exasol_nodes") {
                    next
                }

                # Parse host entry
                host = $1
                ansible_host = ""

                # Find ansible_host parameter
                for (i = 2; i <= NF; i++) {
                    if ($i ~ /^ansible_host=/) {
                        split($i, kv, "=")
                        ansible_host = kv[2]
                        break
                    }
                }

                # Output in format: host|ansible_host
                print host "|" ansible_host
            }
            ' "$inventory_file")
        fi

        if [[ ${#host_entries[@]} -eq 0 ]]; then
            die "No hosts found in inventory.ini"
        fi

        # Progress tracking

        local ssh_timeout=10
        # These variables are used by parent scope - NOT local
        overall_issues=0
        local ip_mismatches=0

        # Tracking for JSON output
        json_issues=()
        failed_checks=()
        ssh_passed=0
        ssh_failed=0
        services_active=0
        services_failed=0
        cluster_ready="false"
        cluster_status=""
        declare -A state_public_ip_map=()
        declare -A tf_ip_by_host=()

        # Preload public IPs from Terraform state (if available) keyed by host order
        local -a state_public_ips=()
        while IFS= read -r tf_ip; do
            [[ -n "$tf_ip" ]] && state_public_ips+=("$tf_ip")
        done < <(health_load_state_public_ips "$deploy_dir" 2>/dev/null || true)

        if [[ ${#state_public_ips[@]} -gt 0 ]]; then
            local idx=0
            for entry in "${host_entries[@]}"; do
                IFS='|' read -r host_name _ <<<"$entry"
                host_name="${host_name//[[:space:]]/}"
                [[ -z "$host_name" ]] && continue
                if [[ -n "${state_public_ips[$idx]:-}" ]]; then
                    state_public_ip_map["$host_name"]="${state_public_ips[$idx]}"
                    tf_ip_by_host["$host_name"]="${state_public_ips[$idx]}"
                fi
                idx=$((idx + 1))
            done
        fi

        # If update requested, rewrite inventory/ssh_config up front using TF state IPs
        if [[ "$do_update_metadata" == "true" && ${#state_public_ip_map[@]} -gt 0 ]]; then
            for i in "${!host_entries[@]}"; do
                IFS='|' read -r host_name host_ip <<<"${host_entries[$i]}"
                host_name="${host_name//[[:space:]]/}"
                host_ip="${host_ip//[[:space:]]/}"
                [[ -z "$host_name" ]] && continue

                local tf_ip="${state_public_ip_map[$host_name]:-}"
                if [[ -n "$tf_ip" && -n "$host_ip" && "$tf_ip" != "$host_ip" ]]; then
                    health_update_inventory_ip "$inventory_file" "$host_name" "$tf_ip" || true
                    health_update_ssh_config "$ssh_config_file" "$host_name" "$tf_ip" || true
                    health_update_info_file "$deploy_dir/INFO.txt" "$host_ip" "$tf_ip" || true
                    # Update host_entries so SSH checks use new IP
                    host_entries[i]="${host_name}|${tf_ip}"
                elif [[ -n "$tf_ip" ]]; then
                    # Keep ssh_config in sync even if inventory already matches
                    health_update_inventory_ip "$inventory_file" "$host_name" "${host_ip:-$tf_ip}" || true
                    health_update_ssh_config "$ssh_config_file" "$host_name" "$tf_ip" || true
                    if [[ -n "$host_ip" && "$host_ip" != "$tf_ip" ]]; then
                        health_update_info_file "$deploy_dir/INFO.txt" "$host_ip" "$tf_ip" || true
                        host_entries[i]="${host_name}|${tf_ip}"
                    fi
                fi
            done
        fi

        # Determine if we should show detailed output
        local show_details="true"
        [[ "$verbosity" == "quiet" && "$output_format" == "text" ]] && show_details="false"

        if [[ "$output_format" == "text" && "$verbosity" != "quiet" ]]; then
            echo "Health report for $deploy_dir"
            echo "============================================================"
        fi

        # Skip cloud metadata check - we'll verify instance count through SSH connectivity instead
        # Cloud metadata checks require AWS CLI and credentials which may not be available

        # Launch parallel health checks for all hosts
        if [[ "$output_format" == "text" && "$verbosity" != "quiet" ]]; then
            echo "Running health checks on ${#host_entries[@]} host(s) in parallel..."
        fi

        local result_dir
        result_dir=$(get_runtime_temp_dir)
        # Clean old health temp files for these hosts
        for entry in "${host_entries[@]}"; do
            IFS='|' read -r host_name _ <<<"$entry"
            host_name="${host_name//[[:space:]]/}"
            [[ -z "$host_name" ]] && continue
            find "$result_dir" -maxdepth 1 -name "health_${host_name}_*.tmp" -delete 2>/dev/null || true
        done

        local -a result_files=()
        local -a host_pids=()
        local idx=0
        for entry in "${host_entries[@]}"; do
            IFS='|' read -r host_name host_ip <<<"$entry"
            host_name="${host_name//[[:space:]]/}"
            host_ip="${host_ip//[[:space:]]/}"

            if [[ -z "$host_name" ]]; then
                continue
            fi

            # Check if this is the first host (for cluster state check)
            local check_cluster="false"
            [[ "$idx" -eq 0 ]] && check_cluster="true"

            # Launch health check in background
            (
                health_check_single_host "$ssh_config_file" "$host_name" "$host_ip" "$ssh_timeout" "$cloud_provider" "$check_cluster" "$result_dir" "$deploy_dir" >/dev/null
            ) &
            host_pids+=($!)

            idx=$((idx + 1))
        done

        # Show progress while waiting for results
        if [[ "$output_format" == "text" && "$verbosity" != "quiet" ]]; then
            local completed=0
            while [[ $completed -lt ${#host_pids[@]} ]]; do
                completed=0
                for pid in "${host_pids[@]}"; do
                    if ! kill -0 "$pid" 2>/dev/null; then
                        completed=$((completed + 1))
                    fi
                done
                if [[ $completed -lt ${#host_pids[@]} ]]; then
                    echo -ne "\rProgress: $completed/${#host_pids[@]} hosts checked..."
                    sleep 0.5
                fi
            done
            echo -e "\rProgress: ${#host_pids[@]}/${#host_pids[@]} hosts checked   "
            echo ""
        fi

        # Wait for all background jobs to complete
        for pid in "${host_pids[@]}"; do
            wait "$pid" 2>/dev/null || true
        done

        # Collect all result files
        for entry in "${host_entries[@]}"; do
            IFS='|' read -r host_name host_ip <<<"$entry"
            host_name="${host_name//[[:space:]]/}"

            if [[ -z "$host_name" ]]; then
                continue
            fi

            # Find the result file (may have different PID)
            local result_file
            result_file=$(find "$result_dir" -maxdepth 1 -name "health_${host_name}_*.tmp" 2>/dev/null | head -1)
            if [[ -n "$result_file" && -f "$result_file" ]]; then
                result_files+=("$result_file")
            fi
        done

        # Process results and display output
        for result_file in "${result_files[@]}"; do
            if [[ ! -f "$result_file" ]]; then
                continue
            fi

            # Read JSON result
            local host_name ansible_host ssh_ok cos_ssh_ok services volume_status local_cluster_status private_ip public_ip port_8443_ok port_8563_ok
            host_name=$(jq -r '.host' "$result_file" 2>/dev/null || echo "unknown")
            ansible_host=$(jq -r '.ansible_host' "$result_file" 2>/dev/null || echo "unknown")
            ssh_ok=$(jq -r '.ssh_ok' "$result_file" 2>/dev/null || echo "false")
            cos_ssh_ok=$(jq -r '.cos_ssh_ok' "$result_file" 2>/dev/null || echo "false")
            services=$(jq -r '.services' "$result_file" 2>/dev/null || echo "")
            volume_status=$(jq -r '.volume_status' "$result_file" 2>/dev/null || echo "")
            local_cluster_status=$(jq -r '.cluster_status' "$result_file" 2>/dev/null || echo "")
            # Update global cluster_status if this host has cluster info
            [[ -n "$local_cluster_status" ]] && cluster_status="$local_cluster_status"
            private_ip=$(jq -r '.private_ip' "$result_file" 2>/dev/null || echo "")
            public_ip=$(jq -r '.public_ip' "$result_file" 2>/dev/null || echo "")
            port_8443_ok=$(jq -r '.port_8443_ok' "$result_file" 2>/dev/null || echo "false")
            port_8563_ok=$(jq -r '.port_8563_ok' "$result_file" 2>/dev/null || echo "false")
            local host_changed="false"

            # Add issues from this host to global issues
            local host_issues
            host_issues=$(jq -c '.issues[]' "$result_file" 2>/dev/null || echo "")
            if [[ -n "$host_issues" ]]; then
                while IFS= read -r issue; do
                    [[ -n "$issue" ]] && json_issues+=("$issue")
                done <<< "$host_issues"
            fi

            # Count results (for both text and JSON output)
            if [[ "$ssh_ok" == "true" ]]; then
                ssh_passed=$((ssh_passed + 1))
            else
                ssh_failed=$((ssh_failed + 1))
                overall_issues=$((overall_issues + 1))
            fi

            # Count service results
            IFS=';' read -ra service_array <<< "$services"
            for service_status in "${service_array[@]}"; do
                [[ -z "$service_status" ]] && continue
                IFS=':' read -r svc_name svc_state <<< "$service_status"
                if [[ "$svc_state" == "active" ]]; then
                    services_active=$((services_active + 1))
                else
                    services_failed=$((services_failed + 1))
                    overall_issues=$((overall_issues + 1))
                fi
            done

            # Count volume issues
            IFS='|' read -r vol_type vol_count vol_sizes <<< "$volume_status"
            if [[ "$vol_type" == "no_data_volumes" || "$vol_type" == "broken_volume_symlink" ]]; then
                overall_issues=$((overall_issues + 1))
            fi

            # Count IP mismatches
            if [[ -n "$public_ip" && -n "$ansible_host" && "$public_ip" != "$private_ip" && "$public_ip" != "$ansible_host" ]]; then
                ip_mismatches=$((ip_mismatches + 1))
                overall_issues=$((overall_issues + 1))
            fi

            # Count port issues
            if [[ "$port_8443_ok" != "true" && -n "$public_ip" ]]; then
                overall_issues=$((overall_issues + 1))
            fi
            if [[ "$port_8563_ok" != "true" && -n "$public_ip" ]]; then
                overall_issues=$((overall_issues + 1))
            fi

            # Track cluster readiness (for status update logic)
            if [[ "$local_cluster_status" == "cluster_stage_d" ]]; then
                cluster_ready="true"
            fi

            # Now display (only for text output)
            if [[ "$output_format" == "text" && "$show_details" == "true" ]]; then
                echo "- Host: $host_name (ansible_host=${ansible_host})"

                # SSH check
                if [[ "$ssh_ok" == "true" ]]; then
                    echo "    ✓ SSH: OK"
                else
                    echo "    ✗ SSH: FAILED (host unreachable)"
                    failed_checks+=("$host_name: SSH unreachable")

                    # If we have public IPs from Terraform state, try to update inventory/ssh_config even when SSH failed
                    if [[ "$do_update_metadata" == "true" ]]; then
                        local state_ip=""
                        state_ip="${state_public_ip_map[$host_name]:-}"
                        if [[ -n "$state_ip" && "$state_ip" != "$ansible_host" ]]; then
                            if health_update_inventory_ip "$inventory_file" "$host_name" "$state_ip"; then
                                health_update_ssh_config "$ssh_config_file" "$host_name" "$state_ip"
                                health_update_info_file "$deploy_dir/INFO.txt" "$ansible_host" "$state_ip"
                                echo "    ✓ IP updated from Terraform state: now $state_ip"
                                host_changed="true"
                            fi
                        fi
                    fi

                    continue
                fi

                # COS SSH check
                if [[ "$cos_ssh_ok" == "true" ]]; then
                    echo "    ✓ COS SSH (${host_name}-cos): OK"
                elif grep -Eq "^Host[[:space:]]+${host_name}-cos" "$ssh_config_file" 2>/dev/null; then
                    echo "    ✗ COS SSH (${host_name}-cos): FAILED"
                    failed_checks+=("$host_name: COS SSH unreachable")
                fi

                # Service checks (display only - already counted above)
                IFS=';' read -ra service_array <<< "$services"
                for service_status in "${service_array[@]}"; do
                    if [[ -z "$service_status" ]]; then
                        continue
                    fi
                    IFS=':' read -r svc_name svc_state <<< "$service_status"
                    if [[ "$svc_state" == "active" ]]; then
                        echo "    ✓ Service $svc_name: active"
                    else
                        echo "    ✗ Service $svc_name: $svc_state"
                        failed_checks+=("$host_name: Service $svc_name is $svc_state")
                    fi
                done

                # Volume check (display only - already counted above)
                IFS='|' read -r vol_type vol_count vol_sizes <<< "$volume_status"
                if [[ "$vol_type" == "volume_ok" ]]; then
                    if [[ -n "$vol_sizes" ]]; then
                        echo "    ✓ Volume check: OK ($vol_count disk(s) found: $vol_sizes)"
                    else
                        echo "    ✓ Volume check: OK ($vol_count disk(s) found)"
                    fi
                elif [[ "$vol_type" == "no_data_volumes" ]]; then
                    echo "    ✗ Volume check: WARNING - No exasol_data_* symlinks detected"
                    failed_checks+=("$host_name: No data volumes detected")
                elif [[ "$vol_type" == "broken_volume_symlink" ]]; then
                    echo "    ✗ Volume check: WARNING - Broken symlinks: $vol_sizes"
                    failed_checks+=("$host_name: Broken volume symlinks")
                fi

                # Cluster state
                if [[ "$local_cluster_status" == "cluster_stage_d" ]]; then
                    echo "    ✓ Cluster state: Stage 'd' - Database ready (all nodes)"
                    cluster_ready="true"
                elif [[ "$local_cluster_status" == "cluster_stage_a" ]]; then
                    echo "    ○ Cluster state: Stage 'a/a1' - Stopped (instances running, database stopped)"
                elif [[ "$local_cluster_status" == "cluster_stage_b" ]]; then
                    echo "    ⚠ Cluster state: Stage 'b/b1' - Boot stage (services starting)"
                    failed_checks+=("$host_name: Cluster in boot stage")
                elif [[ "$local_cluster_status" == "cluster_stage_c" ]]; then
                    echo "    ⚠ Cluster state: Stage 'c' - COS ready (database not started)"
                    failed_checks+=("$host_name: Cluster at COS stage, database not ready")
                elif [[ "$local_cluster_status" == cluster_stage_mixed:* ]]; then
                    local stages="${local_cluster_status#cluster_stage_mixed:}"
                    echo "    ✗ Cluster state: Mixed stages across nodes ($stages)"
                    failed_checks+=("$host_name: Cluster has mixed stages: $stages")
                elif [[ "$local_cluster_status" == "cluster_state_unknown" ]]; then
                    echo "    Cluster state: Unable to verify (c4 ps unavailable)"
                fi

                # IP information
                if [[ -n "$private_ip" ]]; then
                    echo "    ✓ Private IP: $private_ip"
                fi

                # Decide desired IP to use for metadata updates: prefer TF state, then detected public_ip, else ansible_host
                local desired_ip="$ansible_host"
                if [[ -n "${state_public_ip_map[$host_name]:-}" ]]; then
                    desired_ip="${state_public_ip_map[$host_name]}"
                elif [[ -n "$public_ip" && "$public_ip" != "$private_ip" ]]; then
                    desired_ip="$public_ip"
                fi

                # Apply updates if requested
                if [[ "$do_update_metadata" == "true" && -n "$desired_ip" ]]; then
                    local inv_changed="false"
                    local ssh_changed="false"

                    if health_update_inventory_ip "$inventory_file" "$host_name" "$desired_ip"; then
                        inv_changed="true"
                    fi
                    if health_update_ssh_config "$ssh_config_file" "$host_name" "$desired_ip"; then
                        ssh_changed="true"
                    fi
                    if health_update_info_file "$deploy_dir/INFO.txt" "$ansible_host" "$desired_ip"; then
                        host_changed="true"
                    fi

                    if [[ "$inv_changed" == "true" || "$ssh_changed" == "true" || "$host_changed" == "true" ]]; then
                        echo "    ✓ IP metadata updated to $desired_ip"
                        ansible_host="$desired_ip"
                    fi
                fi

                # IP mismatch check (display only)
                if [[ -n "$public_ip" && -n "$ansible_host" && "$public_ip" != "$private_ip" ]]; then
                    if [[ "$public_ip" == "$ansible_host" ]]; then
                        echo "    ✓ Public IP: $public_ip (matches inventory)"
                    else
                        echo "    ✗ IP mismatch: inventory has $ansible_host, cloud metadata shows $public_ip"
                        failed_checks+=("$host_name: IP mismatch (inventory=$ansible_host, actual=$public_ip)")
                    fi
                elif [[ -n "$public_ip" && "$public_ip" == "$private_ip" ]]; then
                    echo "    ⓘ Public IP: Cannot verify (cloud metadata not accessible, inventory shows $ansible_host)"
                fi

                # Port checks (display only - already counted above)
                if [[ "$port_8443_ok" == "true" ]]; then
                    echo "    ✓ Admin UI (8443): HTTPS reachable"
                elif [[ -n "$public_ip" ]]; then
                    echo "    ✗ Admin UI (8443): FAILED"
                    failed_checks+=("$host_name: Admin UI port 8443 unreachable")
                fi

                if [[ "$port_8563_ok" == "true" ]]; then
                    echo "    ✓ DB port (8563): reachable"
                elif [[ -n "$public_ip" ]]; then
                    echo "    ✗ DB port (8563): FAILED"
                    failed_checks+=("$host_name: DB port 8563 unreachable")
                fi
            fi

            # Clean up result file
            rm -f "$result_file"
        done

        # Clean up any remaining health temp files for this run
        find "$result_dir" -maxdepth 1 -name "health_*.tmp" -delete 2>/dev/null || true

        # Update deployment status if health checks pass and --update is used
        # This must happen AFTER all issues are counted above
        if [[ "$do_update_metadata" == "true" && "$update_status" == "true" ]]; then
            local current_status
            current_status=$(state_get_status "$deploy_dir")

            # Auto-correction transition table:
            # +----------------------+---------------------------------------------+---------------------------+------------------------------------------------+
            # | Current Status       | Health Check Result                        | New Status                | Rationale                                      |
            # +----------------------+---------------------------------------------+---------------------------+------------------------------------------------+
            # | database_ready       | cluster_status != "cluster_stage_d"        | database_connection_failed| Database should be ready (stage d) but isn't   |
            # | stopped              | ssh_passed > 0                              | stop_failed               | Claims stopped but SSH still reachable          |
            # | started              | overall_issues == 0 && cluster_ready == "true"| database_ready           | Infrastructure powered on and cluster is ready |
            # | deployment_failed    | overall_issues == 0 && cluster_ready == "true"| database_ready           | Claims failed but cluster is healthy            |
            # | database_connection_failed | overall_issues == 0 && cluster_ready == "true"| database_ready           | Claims connection failed but cluster is healthy |
            # | start_failed         | overall_issues == 0 && cluster_ready == "true"| database_ready           | Claims start failed but cluster is running     |
            # | stop_failed          | overall_issues == 0 && cluster_ready == "true"| database_ready           | Claims stop failed but cluster is running      |
            # | stop_failed          | ssh_passed == 0 && ssh_failed == cluster_size | stopped                  | Claims stop failed but all nodes are unreachable|
            # | destroy_failed       | overall_issues == 0 && cluster_ready == "true"| database_ready           | Claims destroy failed but cluster is running    |
            # +----------------------+---------------------------------------------+---------------------------+------------------------------------------------+

            # Use the shared status determination logic
            local determined_status
            determined_status=$(health_determine_status "$deploy_dir" "$ssh_passed" "$ssh_failed" "$cluster_status" "$overall_issues")

            # Update status if it changed
            if [[ "$determined_status" != "$current_status" ]]; then
                case "$determined_status" in
                    database_ready)
                        state_set_status "$deploy_dir" "$STATE_DATABASE_READY"
                        if [[ "$output_format" == "text" && "$verbosity" != "quiet" ]]; then
                            log_info "✅ Deployment status updated to 'database_ready' (cluster is healthy and running)"
                        fi
                        ;;
                    stopped)
                        state_set_status "$deploy_dir" "$STATE_STOPPED"
                        if [[ "$output_format" == "text" && "$verbosity" != "quiet" ]]; then
                            log_info "✅ Deployment status updated to 'stopped' (all nodes unreachable, VMs are powered off)"
                        fi
                        ;;
                    database_connection_failed)
                        state_set_status "$deploy_dir" "$STATE_DATABASE_CONNECTION_FAILED"
                        if [[ "$output_format" == "text" && "$verbosity" != "quiet" ]]; then
                            log_info "✅ Deployment status updated to 'database_connection_failed' (database not in ready stage)"
                        fi
                        ;;
                    stop_failed)
                        state_set_status "$deploy_dir" "$STATE_STOP_FAILED"
                        if [[ "$output_format" == "text" && "$verbosity" != "quiet" ]]; then
                            log_info "✅ Deployment status updated to 'stop_failed' (instances reachable via SSH but should be stopped)"
                        fi
                        ;;
                esac
            fi
        fi

}
