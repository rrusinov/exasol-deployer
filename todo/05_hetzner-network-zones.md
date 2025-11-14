# Wire Hetzner Network Zones End-to-End (LATER)

## Issue
`hetzner_network_zone` is defined in `templates/terraform-hetzner/variables.tf` but `main.tf` hardcodes `"eu-central"` for the subnet and `cmd_init`/README never expose the option. Users cannot choose zones such as `us-east`.

## Recommendation
Add a `--hetzner-network-zone` flag in `lib/cmd_init.sh`, pass it through `write_provider_variables`, document it in `README.md`, and use `var.hetzner_network_zone` for `hcloud_network_subnet.network_zone`.

## Next Steps
1. Update CLI help, Terraform variables file generation, and the Hetzner template
2. Add tests/validation ensuring non-default zones apply correctly

## Status
Marked as "LATER NOT NOW" - lower priority infrastructure improvement