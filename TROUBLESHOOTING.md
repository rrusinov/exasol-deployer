# Troubleshooting Guide

## Manual Power Control

Some cloud providers don't support automatic power on/off via API. When you run `exasol start` on these providers, you'll see instructions for manual power-on:

### Hetzner
```bash
# Web Console
# Go to: https://console.hetzner.cloud/
# Navigate to your server and click "Power On"

# CLI (requires hcloud CLI)
hcloud server list  # Find your server name
hcloud server poweron <server-name>
```

### DigitalOcean
```bash
# Web Console
# Go to: https://cloud.digitalocean.com/droplets
# Find your droplet and click "Power On"

# CLI (requires doctl CLI)
doctl compute droplet list  # Find your droplet ID
doctl compute droplet-action power-on <droplet-id>
```

### libvirt (Local VMs)
```bash
# List all VMs
virsh list --all

# Start a specific VM
virsh start <vm-name>

# Alternative: Use virt-manager GUI
virt-manager
```

**Note:** After manually powering on, the `start` command will automatically detect when the servers are online and continue with database startup.

## Common Issues

### "Provider X does not support automatic power control"
This is expected behavior for Hetzner, DigitalOcean, and libvirt. Follow the manual power-on instructions displayed.

### Start command times out waiting for health
- Check that servers are powered on and reachable via SSH
- Verify network connectivity between nodes
- Check system logs: `journalctl -u exasol-overlay` and `journalctl -u c4_cloud_command`

### Overlay network issues
- VXLAN port 4789 is used internally for cluster communication between nodes (not required in firewall rules for external access)
- Check overlay service status: `systemctl status exasol-overlay`
- Verify bridge interface exists: `ip addr show vxlan-br0`

### SSH Connection Issues
```bash
# Test SSH connectivity
ssh -F ./my-deployment/ssh_config n11

# Check SSH key permissions
chmod 600 ./my-deployment/exasol-key.pem

# Verify instance is running
./exasol status --deployment-dir ./my-deployment
```

### Database Connection Issues
```bash
# Check database status
./exasol health --deployment-dir ./my-deployment

# Check c4 service logs
ssh -F ./my-deployment/ssh_config n11 'journalctl -u c4.service -f'

# Restart database services
ssh -F ./my-deployment/ssh_config n11 'sudo systemctl restart c4.service'
```

## Important Files

- `.exasol.json` - Deployment state (do not modify)
- `variables.auto.tfvars` - OpenTofu variables
- `.credentials.json` - Passwords (DB/AdminUI/host; keep secure)
- `terraform.tfstate` - OpenTofu state (created after deployment)

## Getting Help

1. Check the [Cloud Setup Guides](clouds/CLOUD_SETUP.md) for provider-specific issues
2. Review the [Testing Documentation](tests/README.md) for debugging techniques
3. Run health checks with `./exasol health --deployment-dir ./my-deployment --update`
4. Check deployment logs in the deployment directory
