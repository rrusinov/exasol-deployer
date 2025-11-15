# Implement Health Check & Auto-Recovery for Spontaneous Reboots

Create a proactive health-check command that detects unexpected provider-initiated instance reboots, validates the deployment state, and optionally self-heals the environment (e.g., reinitializing services or refreshing IP metadata). This complements the `start/stop/reboot` work by covering unplanned outages.

## Command Overview

- `exasol health --deployment-dir <dir> [--update] [--try-fix]`
  - Default: read-only health report
  - `--update`: refresh local artifacts (`inventory.ini`, Terraform state, INFO.txt, cached IP lists) to match the live environment
  - `--try-fix`: attempt automated remediation (restart services, re-run Ansible checks, re-sync cluster metadata) if issues are detected

## Detection & Validation
- **Instance Reachability**: Ping/SSH each node (both OS and COS SSH endpoints) to detect reboots or unreachable hosts
- **Cloud Metadata Check**: Query provider APIs (or rely on `./exasol status --show-details`) to confirm the number of running instances and their IPs match expected values
- **Service Health**: Run on-node probes (systemctl, Exasol service checks, database ping, AdminUI port) to ensure services recovered after reboot. Example c4-deployed systemd units to verify on AWS:
  - `c4.service`
  - `c4_cloud_command.service`
  - `exasol-admin-ui.service`
  - `exasol-data-symlinks.service`
  After spontaneous reboots, health checks should confirm these services are active (`systemctl status ...`) and that Admin UI logs (`journalctl -u exasol-admin-ui`) show fresh startup messages (e.g., “Starting AdminUI HTTPS server…”) indicating a clean restart.
- **IP Consistency**: Compare live IPs with local files (`inventory.ini`, `variables.auto.tfvars`, Terraform state, INFO.txt); report discrepancies and optionally fix them with `--update`
- **Volume Attachments**: Validate that data/root volumes are still attached after reboot
- **Cluster State**: For multi-node deployments, ensure all nodes rejoined the cluster and cluster metadata is consistent

## Error Classification
- Node unreachable vs. service down
- IP mismatch vs. Terraform state mismatch
- Volume missing vs. service failure
Document these in the health report so operators know next steps.

## Remediation (`--try-fix`)
- Restart failed services via Ansible/SSH
- Re-run symlink/volume initialization scripts if necessary
- Refresh inventory/state files if IPs changed
- Optionally trigger a `reboot` or `start` command for nodes that failed to recover
- Keep backups of modified files when auto-updating

## Logging & Reporting
- Detailed JSON and human-readable output summarizing health check results
- Exit codes: `0` for healthy, `1` for diagnosed issues, `2` for failed remediation

## Integration Points
- Shares locking/state logic with start/stop commands
- Can be scheduled (cron/CI) to run periodically for early detection
- Later could integrate with monitoring/alerting systems

## Success Criteria
- Health command detects spontaneous reboots and service degradations
- Reports precise root causes (unreachable nodes, mismatched IPs, failed services)
- `--update` keeps local metadata synchronized with live infrastructure
- `--try-fix` can automatically restore common failure modes without manual intervention
