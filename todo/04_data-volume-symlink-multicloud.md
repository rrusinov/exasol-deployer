# Make Data-Volume Symlink Script Multi-Cloud

## Issue
`templates/ansible/exasol-data-symlinks.sh.j2` searches only for `/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_*`, which exists solely on AWS. The play fails on Azure/GCP/Hetzner/DigitalOcean despite Terraform exporting their volume IDs.

## Recommendation
Detect the cloud (via facts or inventory vars) and implement per-provider discovery:
- Azure: `SCSI_LUN`
- GCP: `/dev/disk/by-id/google-*`
- Hetzner: `/dev/disk/by-id/scsi-0HC_Volume_*`

Alternatively, replace the provider-specific logic with `lsblk`-based matching keyed by the volume IDs passed from Terraform.

## Next Steps
1. Prototype the discovery logic on each provider
2. Update the systemd unit script/template
3. Add integration tests that ensure the play continues past Section 3A on non-AWS clouds