# Deduplicate Terraform Inventory Generation

## Issue
Each provider copies the same `local_file "ansible_inventory"` resource, which makes changes error-prone.

## Recommendation
Move the resource (and common inputs/depends_on logic) into `terraform-common/common.tf`, feeding it only via shared locals (`node_public_ips`, `node_private_ips`, `node_volumes`).

## Next Steps
1. Extract the shared block into `terraform-common/common.tf`
2. Update provider modules to rely on it (just ensuring locals exist)
3. Adjust tests referencing provider-specific inventory files