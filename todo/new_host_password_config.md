
# Host Password Configuration

## Overview
Add support for a configurable host password (`host_password`) for Exasol node OS-level access. This should follow the same pattern as `db_password` and `adminui_password`: user-supplied via CLI or randomly generated, securely stored, and injected into deployment artifacts. This parameter is common for all cloud providers.

## Implementation Plan

### 1. CLI Support (`lib/cmd_init.sh`)
- Add `--host-password <password>` option to the `init` command (default: random 16 chars if not specified).
- Update help text and documentation to include this option.
- Use the same password generation logic as for other passwords.
- Store `host_password` in `.credentials.json` alongside other credentials.

### 2. Template Injection
- Update Ansible and Terraform templates to use the new password variable.
- For Ansible: set `CCC_HOST_IMAGE_PASSWORD={{ exa_host_password }}` in `config.j2`.
- For Terraform/cloud-init: ensure variable is available for VM provisioning.

### 3. Documentation
- Update `README.md` and all relevant setup guides to document the new `--host-password` option.
- Clearly explain that the host password is for OS-level login to Exasol cluster nodes (e.g., `exasol@n11`).
- Note security best practices and retrieval instructions.

### 4. Testing
- Add/extend tests in `test_common.sh` and E2E framework to validate password generation, storage, and injection.
- Add test cases for CLI parsing, credentials file output, and template usage.
- Ensure password is correctly set on deployed VMs and accessible via SSH.

## Consistency Checklist
- Naming: Use `host_password` everywhere, matching other password variables.
- Storage: `.credentials.json` structure remains consistent.
- Generation: Follows same randomization and length as other passwords.
- Injection: Mirrors how other passwords are injected into templates and provisioning scripts.
- Documentation: Follows the same format and location as existing password documentation.

## Testing Strategy
- Verify `--host-password` option accepts custom passwords.
- Verify random generation when option not provided.
- Verify `.credentials.json` contains `host_password`.
- Verify Ansible and Terraform templates use the correct variable.
