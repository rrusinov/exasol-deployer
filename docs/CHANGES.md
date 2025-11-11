# Template Modifications - Summary

## Overview

Modified the Terraform and Ansible templates to use parameters from the `init` command and to intelligently handle file downloads based on URL scheme (file:// vs http(s)://).

## Key Changes

### 1. Enhanced Configuration Storage

**File**: [`lib/cmd_init.sh`](lib/cmd_init.sh)

The `.credentials.json` file now stores additional metadata:
```json
{
  "db_password": "...",
  "adminui_password": "...",
  "db_download_url": "https://... or file://...",
  "c4_download_url": "https://... or file://...",
  "created_at": "2025-01-15T10:30:00Z"
}
```

This allows Ansible to access the download URLs configured during initialization.

### 2. Smart Download Logic in Deploy Command

**File**: [`lib/cmd_deploy.sh`](lib/cmd_deploy.sh)

The deploy command now:
- Reads download URLs from `.credentials.json`
- Checks if URLs start with `file://`
- **For file:// URLs**: Copies files from local filesystem to `.version-files/` directory
- **For http(s):// URLs**: Lets Ansible download directly on remote nodes (no local download)

**Example**:
```bash
# file:// URL - files copied locally, then transferred via Ansible
DB_DOWNLOAD_URL=file:///Users/me/releases/exasol-8.0.0.tar.gz

# https:// URL - Ansible downloads directly on remote nodes
DB_DOWNLOAD_URL=https://s3.amazonaws.com/releases/exasol-8.0.0.tar.gz
```

### 3. Ansible Playbook Improvements

**File**: [`templates/ansible/setup-exasol-cluster.yml`](templates/ansible/setup-exasol-cluster.yml)

#### Configuration Loading
- Loads `.credentials.json` at playbook start
- Extracts passwords and download URLs
- Determines transfer method based on URL scheme

```yaml
- name: Load credentials and configuration
  ansible.builtin.set_fact:
    deployment_config: "{{ lookup('file', playbook_dir + '/../.credentials.json') | from_json }}"

- name: Determine if using local files
  ansible.builtin.set_fact:
    use_local_files: "{{ db_download_url.startswith('file://') }}"
```

#### Conditional File Transfer

**For file:// URLs** (Section 3 - File Transfer block):
```yaml
- name: Transfer files using file transfer method (for file:// URLs)
  when: use_local_files | bool
  block:
    - name: Get stats and checksums of local release files
      ansible.builtin.stat:
        path: "{{ item }}"
        checksum_algorithm: sha256
      with_fileglob:
        - "{{ version_files_dir }}/c4*"
        - "{{ version_files_dir }}/exasol-*.tar.gz"

    - name: Transfer release files from local paths
      ansible.builtin.include_tasks: transfer_file.yml
```

**For http(s):// URLs** (Section 3 - Direct Download block):
```yaml
- name: Download files directly (for http(s):// URLs)
  when: not (use_local_files | bool)
  block:
    - name: Download Exasol database tarball
      ansible.builtin.get_url:
        url: "{{ db_download_url }}"
        dest: "/home/{{ initial_user }}/exasol-release/..."
        retries: 3

    - name: Download c4 binary
      ansible.builtin.get_url:
        url: "{{ c4_download_url }}"
        dest: "/home/{{ initial_user }}/exasol-release/..."
        mode: '0755'
        retries: 3
```

#### Password Handling
Passwords from `.credentials.json` are now used directly in the config template:
```yaml
- name: Create final Exasol config file from template
  ansible.builtin.template:
    src: "{{ playbook_dir }}/config.j2"
  vars:
    exa_db_password: "{{ deployment_config.db_password }}"
    exa_admin_password: "{{ deployment_config.adminui_password }}"
```

### 4. Simplified transfer_file.yml

**File**: [`templates/ansible/transfer_file.yml`](templates/ansible/transfer_file.yml)

Simplified to handle only local file copying (no HTTP cache fallback):
```yaml
- name: "Transfer file: {{ file_item.item | basename }}"
  ansible.builtin.copy:
    src: "{{ file_item.item }}"
    dest: "{{ dest_path }}"
    owner: "{{ initial_user }}"
    group: "{{ initial_user }}"
    mode: "{{ '0755' if (file_item.item | basename).startswith('c4') else '0644' }}"
```

This file is **only used when URLs start with file://**.

### 5. Updated versions.conf

**File**: [`versions.conf`](versions.conf)

Added documentation and example for file:// URLs:
```ini
# Note: URLs can be either HTTP(S) or file://
# - HTTP(S) URLs: Files are downloaded directly on remote nodes during Ansible playbook
# - file:// URLs: Files are copied from local filesystem and transferred via Ansible

# Example: Using local files with file:// URLs
#[8.0.0-x86_64-local]
#ARCHITECTURE=x86_64
#DB_VERSION=8.0.0
#DB_DOWNLOAD_URL=file:///Users/username/releases/exasol-8.0.0.tar.gz
#C4_DOWNLOAD_URL=file:///Users/username/releases/c4
```

## Workflow Comparison

### With HTTP(S) URLs (Remote Download)

```
1. User runs: ./exasol init --db-version 8.0.0-x86_64
   → Stores URLs in .credentials.json

2. User runs: ./exasol deploy
   → Detects http(s):// URLs
   → Creates empty .version-files/ directory
   → Runs Terraform
   → Runs Ansible:
      ├─ Ansible downloads tarball from URL to remote node
      ├─ Ansible downloads c4 from URL to remote node
      └─ Continues with cluster setup
```

**Advantages**:
- No local bandwidth usage
- Faster for remote files
- Files downloaded directly where needed

### With file:// URLs (Local Files)

```
1. User runs: ./exasol init --db-version 8.0.0-x86_64-local
   → Stores file:// URLs in .credentials.json

2. User runs: ./exasol deploy
   → Detects file:// URLs
   → Extracts local paths (removes file:// prefix)
   → Copies files to .version-files/ directory
   → Runs Terraform
   → Runs Ansible:
      ├─ Ansible transfers tarball from .version-files/ to remote node
      ├─ Ansible transfers c4 from .version-files/ to remote node
      └─ Continues with cluster setup
```

**Advantages**:
- Works with local/private releases
- No internet requirement for files
- Consistent with existing workflow

## Configuration Parameters Usage

All parameters from `init` command are now used:

| Parameter | Stored In | Used By |
|-----------|-----------|---------|
| `--db-version` | `.exasol.json` | Terraform (via state), Ansible (version files) |
| `--cluster-size` | `variables.auto.tfvars` (node_count) | Terraform |
| `--instance-type` | `variables.auto.tfvars` | Terraform |
| `--data-volume-size` | `variables.auto.tfvars` | Terraform |
| `--db-password` | `.credentials.json` | Ansible (config.j2 template) |
| `--adminui-password` | `.credentials.json` | Ansible (config.j2 template) |
| `--owner` | `variables.auto.tfvars` | Terraform (resource tags) |
| `--aws-region` | `variables.auto.tfvars` | Terraform |
| `--aws-profile` | `variables.auto.tfvars` | Terraform |
| `--allowed-cidr` | `variables.auto.tfvars` | Terraform (security groups) |
| Download URLs | `.credentials.json` | Deploy script & Ansible |

## Testing

### Test with HTTP URLs (default)
```bash
./exasol init --deployment-dir ./test-http
./exasol deploy --deployment-dir ./test-http
# Ansible will download files from HTTP URLs on remote nodes
```

### Test with file:// URLs
```bash
# 1. Create a local version entry in versions.conf
# 2. Initialize with that version
./exasol init --deployment-dir ./test-local --db-version 8.0.0-x86_64-local
./exasol deploy --deployment-dir ./test-local
# Deploy will copy local files, then Ansible transfers them
```

## Benefits

1. **Flexibility**: Support both remote downloads and local files
2. **Efficiency**: Remote downloads save local bandwidth and time
3. **Parameter Integration**: All init parameters properly flow through to Terraform and Ansible
4. **Simplicity**: Single playbook handles both scenarios with conditional logic
5. **Maintainability**: Clear separation of concerns between deploy script and Ansible

## Files Modified

1. [`lib/cmd_init.sh`](lib/cmd_init.sh) - Store download URLs in credentials
2. [`lib/cmd_deploy.sh`](lib/cmd_deploy.sh) - Smart file handling based on URL scheme
3. [`templates/ansible/setup-exasol-cluster.yml`](templates/ansible/setup-exasol-cluster.yml) - Load config, conditional downloads
4. [`templates/ansible/transfer_file.yml`](templates/ansible/transfer_file.yml) - Simplified local file transfer
5. [`versions.conf`](versions.conf) - Added documentation and examples

## Backward Compatibility

The changes are **backward compatible**:
- Existing HTTP(S) URLs work as before (but with improved efficiency)
- New file:// URLs enable local file support
- All existing deployments continue to work
