# Utility Scripts

This directory contains operational and development utility scripts for the Exasol Deployer project.

**Note:** These scripts are for development and operational use only. **They are not included in packaged releases** because they require cloud provider CLI tools (aws, az, gcloud, hcloud, doctl, virsh) to be installed on the system.

## Quick Reference

| Script | Purpose |
|--------|---------|
| `generate-limits-report.sh` | Generate HTML report of cloud limits across all regions |
| `cleanup-resources.sh` | Bulk cleanup of cloud resources |

## Prerequisites

These scripts require cloud provider CLI tools to be installed:

- **AWS**: `aws` CLI ([installation](https://aws.amazon.com/cli/))
- **Azure**: `az` CLI ([installation](https://docs.microsoft.com/cli/azure/install-azure-cli))
- **GCP**: `gcloud` CLI ([installation](https://cloud.google.com/sdk/docs/install))
- **Hetzner**: `hcloud` CLI ([installation](https://github.com/hetznercloud/cli))
- **DigitalOcean**: `doctl` CLI ([installation](https://docs.digitalocean.com/reference/doctl/))
- **libvirt**: `virsh` command (part of libvirt-client package)

The scripts will skip providers whose CLI tools are not installed.

## Quick Start

### Generate Limits Report

```bash
# Full report for all providers (scans all regions)
./scripts/generate-limits-report.sh --output report.html

# Specific provider
./scripts/generate-limits-report.sh --provider azure --output azure.html

# Open in browser (Linux)
xdg-open report.html
```

**Features:**
- Scans all major regions automatically
- Shows running instances with tags (owner, creator, project)
- Displays resource quotas and usage percentages
- Interactive expandable sections

### Cleanup Resources

```bash
# Dry run (preview only)
./scripts/cleanup-resources.sh --provider aws --dry-run

# Actually delete
./scripts/cleanup-resources.sh --provider aws --yes
```

## Testing

All scripts have unit tests in the `tests/` directory:

```bash
# Run all tests
./tests/run_tests.sh

# Run specific script tests
./tests/test_generate_limits_report.sh
```

## Development

When adding new scripts:

1. Follow the code style in [AGENTS.md](../AGENTS.md)
2. Add unit tests in `tests/test_<script_name>.sh`
3. Link tests in `tests/run_tests.sh`
4. Update this README

## Support

For issues or questions, see the [main project README](../README.md).
