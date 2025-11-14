# Fix Hetzner Private IP Outputs

## Issue
`local.node_private_ips` in `templates/terraform-hetzner/main.tf` reuses the public IP list, even though each server receives a private address via `hcloud_server_network`.

## Recommendation
Capture the IPs from `hcloud_server_network.exasol_node_network[*].ip` (or a data lookup) so Terraform outputs/INFO files expose the actual private network addresses.

## Next Steps
1. Adjust the local definition in `templates/terraform-hetzner/main.tf`
2. Ensure the inventory template sees the new values
3. Extend tests that read `node_private_ips`