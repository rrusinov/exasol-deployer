# Cloud Provider Setup Guides

This directory contains detailed setup guides for each supported cloud provider.

## Supported Providers

- **[AWS (Amazon Web Services)](CLOUD_SETUP_AWS.md)** - Most feature-complete with spot instances
- **[Azure (Microsoft Azure)](CLOUD_SETUP_AZURE.md)** - Full support with low-priority instances
- **[GCP (Google Cloud Platform)](CLOUD_SETUP_GCP.md)** - Full support with preemptible instances
- **[Hetzner Cloud](CLOUD_SETUP_HETZNER.md)** - Cost-effective European provider
- **[DigitalOcean](CLOUD_SETUP_DIGITALOCEAN.md)** - Simple and affordable
- **[Local libvirt/KVM](CLOUD_SETUP_LIBVIRT.md)** - Local testing and development

## General Setup Guide

See [CLOUD_SETUP.md](CLOUD_SETUP.md) for an overview of all providers and common setup patterns.

## Quick Reference

| Provider | Automatic Power Control | Spot/Preemptible | Multi-Region |
|----------|------------------------|------------------|--------------|
| AWS | ✅ Yes | ✅ Yes | ✅ Yes |
| Azure | ✅ Yes | ✅ Yes | ✅ Yes |
| GCP | ✅ Yes | ✅ Yes | ✅ Yes |
| Hetzner | ⚠️ Manual | ❌ No | ✅ Yes |
| DigitalOcean | ⚠️ Manual | ❌ No | ✅ Yes |
| libvirt | ⚠️ Manual | N/A | N/A |

**Legend:**
- ✅ Fully supported
- ⚠️ Requires manual intervention
- ❌ Not available
- N/A Not applicable
