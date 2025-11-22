# Exasol Deployment

This directory contains a deployment configuration for Exasol database.

> Note: The libvirt backend is in active development and host-specific. Expect manual tuning per machine; it is not yet a fully portable target like the cloud providers.

## Configuration

- **Cloud Provider**: Local libvirt/KVM deployment
- **Database Version**: exasol-2025.1.4
- **Architecture**: arm64
- **Cluster Size**: 1 nodes
- **Instance Type**: libvirt-custom
- **Local KVM Deployment**
- **Memory**: 4GB per VM
- **vCPUs**: 2 per VM
- **Network**: default
- **Storage Pool**: default

## Credentials

Database and AdminUI credentials are stored in `.credentials.json` (protected file).

## Next Steps

1. Review and customize `variables.auto.tfvars` if needed
2. Run `./exasol deploy --deployment-dir /Users/ruslan.rusinov/work/exasol-deployer/.` to deploy
3. Run `./exasol status --deployment-dir /Users/ruslan.rusinov/work/exasol-deployer/.` to check status
4. Run `./exasol destroy --deployment-dir /Users/ruslan.rusinov/work/exasol-deployer/.` to tear down

## Important Files

- `.exasol.json` - Deployment state (do not modify)
- `variables.auto.tfvars` - Terraform variables
- `.credentials.json` - Passwords (keep secure)
- `terraform.tfstate` - Terraform state (created after deployment)
