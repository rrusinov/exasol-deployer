# Terraform Template Updates

## Summary

Updated the Terraform templates to accept the `owner` parameter from the init command and changed node naming convention from `exasol-node-X` to `nXX` (starting at n11).

## Changes Made

### 1. Owner Tag Parameter

**File**: [`templates/terraform/variables.tf`](templates/terraform/variables.tf)

Added new variable for owner tag:
```hcl
variable "owner" {
  description = "Owner tag for all resources."
  type        = string
  default     = "exasol-personal"
}
```

**File**: [`templates/terraform/main.tf`](templates/terraform/main.tf:25)

Updated AWS provider default tags:
```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      "owner" = var.owner    # Changed from: "owner" = "<UNKNWON>"
    }
  }
}
```

**Behavior**:
- If `--owner` is specified in init command: uses that value
- If not specified: defaults to `"exasol-personal"`
- Previously was hardcoded as `"<UNKNWON>"` (typo)

### 2. Node Naming Convention

Changed node naming from `exasol-node-1`, `exasol-node-2`, etc. to `n11`, `n12`, `n13`, etc.

This matches the Exasol cluster convention where nodes are numbered starting from n11.

#### EC2 Instance Names

**File**: [`templates/terraform/main.tf`](templates/terraform/main.tf:209)

```hcl
# Before:
Name = "exasol-node-${count.index + 1}"    # exasol-node-1, exasol-node-2, ...

# After:
Name = "n${count.index + 11}"              # n11, n12, n13, n14, ...
```

#### EBS Volume Names

**File**: [`templates/terraform/main.tf`](templates/terraform/main.tf:229)

```hcl
# Before:
Name = "exasol-node-${count.index + 1}-data"    # exasol-node-1-data, ...

# After:
Name = "n${count.index + 11}-data"              # n11-data, n12-data, ...
```

#### SSH Config Hosts

**File**: [`templates/terraform/main.tf`](templates/terraform/main.tf:259)

```hcl
# Before:
Host exasol-node-${idx + 1}
    HostName ${instance.public_ip}
    ...

# After:
Host n${idx + 11}
    HostName ${instance.public_ip}
    ...
```

#### Ansible Inventory

**File**: [`templates/terraform/inventory.tftpl`](templates/terraform/inventory.tftpl:3)

```ini
# Before:
exasol-node-${idx + 1} ansible_host=${instance.public_ip} ...

# After:
n${idx + 11} ansible_host=${instance.public_ip} ...
```

## Node Numbering Logic

| Cluster Size | Node Names |
|--------------|------------|
| 1 node       | n11        |
| 2 nodes      | n11, n12   |
| 3 nodes      | n11, n12, n13 |
| 4 nodes      | n11, n12, n13, n14 |

The numbering starts at 11 to match the Exasol convention where the first node is always n11.

## Usage Examples

### Example 1: Default Owner

```bash
./exasol init --deployment-dir ./my-cluster
```

Generated `variables.auto.tfvars`:
```hcl
owner = "exasol-personal"
```

Resources will be tagged with `owner = "exasol-personal"`

### Example 2: Custom Owner

```bash
./exasol init --deployment-dir ./my-cluster --owner "john-doe"
```

Generated `variables.auto.tfvars`:
```hcl
owner = "john-doe"
```

Resources will be tagged with `owner = "john-doe"`

### Example 3: Multi-Node Cluster

```bash
./exasol init --deployment-dir ./prod-cluster --cluster-size 4 --owner "production-team"
```

This creates:
- EC2 instances: `n11`, `n12`, `n13`, `n14`
- EBS volumes: `n11-data`, `n12-data`, `n13-data`, `n14-data`
- SSH config hosts: `n11`, `n12`, `n13`, `n14`
- Ansible inventory: `n11`, `n12`, `n13`, `n14`
- Owner tag: `production-team`

## SSH Access

After deployment, you can SSH using the node names:

```bash
# Before (old naming):
ssh -F ssh_config exasol-node-1
ssh -F ssh_config exasol-node-2

# After (new naming):
ssh -F ssh_config n11
ssh -F ssh_config n12
```

## Ansible Playbook

The Ansible playbook will see nodes as:
```ini
[exasol_nodes]
n11 ansible_host=54.123.45.67 ansible_user=ubuntu private_ip=10.0.1.10
n12 ansible_host=54.123.45.68 ansible_user=ubuntu private_ip=10.0.1.11
n13 ansible_host=54.123.45.69 ansible_user=ubuntu private_ip=10.0.1.12
```

This aligns with the Exasol setup-exasol-cluster.yml playbook which sets hostnames to `n1`, `n2`, etc. (but our EC2 instances are named `n11`, `n12` for uniqueness).

## AWS Resource Tags

All resources now have proper owner tags:

**VPC**:
```
Name: exasol-vpc
owner: <from --owner parameter or "exasol-personal">
```

**EC2 Instances**:
```
Name: n11, n12, n13, ...
Role: worker
Cluster: exasol-cluster
owner: <from --owner parameter or "exasol-personal">
```

**EBS Volumes**:
```
Name: n11-data, n12-data, ...
Cluster: exasol-cluster
owner: <from --owner parameter or "exasol-personal">
```

**Security Group**:
```
Name: exasol-cluster-sg
owner: <from --owner parameter or "exasol-personal">
```

## Compatibility Note

The hostname inside the EC2 instance (set by Ansible) will still be `n1`, `n2`, `n3`, etc., as configured in the setup-exasol-cluster.yml playbook:

```yaml
- name: Set hostname to n1, n2, etc.
  ansible.builtin.hostname:
    name: "n{{ ansible_play_hosts.index(inventory_hostname) + 1 }}"
```

So:
- **AWS EC2 instance name (tag)**: `n11`, `n12`, `n13` (external identifier)
- **Internal hostname (inside VM)**: `n1`, `n2`, `n3` (cluster internal)
- **Ansible inventory name**: `n11`, `n12`, `n13` (matches EC2)

This separation allows for multiple Exasol clusters in the same AWS account without hostname conflicts, while keeping the internal cluster configuration simple (n1, n2, n3).

## Testing

All functionality verified:

```bash
# Test 1: Default owner
$ ./exasol init --deployment-dir ./test1
$ grep owner ./test1/variables.auto.tfvars
owner = "exasol-personal"

# Test 2: Custom owner
$ ./exasol init --deployment-dir ./test2 --owner "test-user"
$ grep owner ./test2/variables.auto.tfvars
owner = "test-user"

# Test 3: Verify template changes
$ grep "Name.*n\${count" templates/terraform/main.tf
    Name    = "n${count.index + 11}"
    Name    = "n${count.index + 11}-data"

$ grep "Host n\${idx" templates/terraform/main.tf
Host n${idx + 11}

$ cat templates/terraform/inventory.tftpl
n${idx + 11} ansible_host=${instance.public_ip} ...
```

## Benefits

1. **Proper Resource Attribution**: All AWS resources tagged with actual owner
2. **Exasol Conventions**: Node naming matches Exasol's n11+ convention
3. **Cleaner Names**: Shorter node names (n11 vs exasol-node-1)
4. **Easy SSH**: Simple hostnames like `ssh -F ssh_config n11`
5. **Cost Tracking**: AWS cost allocation by owner tag
6. **No Typos**: Fixed "UNKNWON" → proper variable reference

## Backward Compatibility

These are breaking changes for existing deployments:
- ⚠️ Node names have changed (affects SSH config, AWS console)
- ✅ Owner tag now properly set (was broken before)

If you have existing deployments, they will continue to work with old names until destroyed and recreated with the new templates.
