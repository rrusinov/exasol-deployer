# Exoscale Terraform Templates

This directory contains Exoscale-specific Terraform templates and scripts.

## Provider-Specific Files

### cloud-init-exoscale.tftpl

Exoscale-specific cloud-init template that configures the private network interface.

**What it does:**
1. Creates netplan configuration for eth1 (private network interface)
2. Brings up eth1 with DHCP to get the assigned private IP
3. Disables routes via private network (keeps default route on public interface)
4. Waits for eth1 to receive IP address before continuing

**Why needed:**
Exoscale attaches private network interfaces but doesn't automatically configure them. Without this, eth1 stays DOWN and Exasol can't bind to the private IP.

### exasol-data-symlinks.sh.j2

Exoscale-specific script for creating stable `/dev/exasol_data_*` symlinks.

**Volume ID Format:**
- Terraform passes full UUID: `d1206e7a-b272-477e-9f48-1ccbc06e8043`
- Device appears as: `/dev/disk/by-id/virtio-d1206e7a-b272-477e-9` (first 19 chars of UUID)
- Device node: `/dev/vdb`, `/dev/vdc`, etc.

**How it works:**
1. Takes volume UUIDs from Terraform (passed via Ansible inventory)
2. Truncates each UUID to first 19 characters
3. Finds matching `/dev/disk/by-id/virtio-<truncated-uuid>*` link
4. Resolves to actual device (`/dev/vd*`)
5. Creates stable symlink: `/dev/exasol_data_01`, `/dev/exasol_data_02`, etc.

**Deployment:**
During `exasol init`, this file overwrites the generic `ansible/exasol-data-symlinks.sh.j2` in the deployment's `.templates/` directory. This is the correct pattern for provider-specific overrides.

## Other Providers

To create a provider-specific symlink script:
1. Create `templates/terraform-<provider>/exasol-data-symlinks.sh.j2`
2. Implement provider-specific device discovery logic
3. The script will automatically override the generic ansible version during `exasol init`

See the generic `templates/ansible/exasol-data-symlinks.sh.j2` for the full pattern with all providers.
