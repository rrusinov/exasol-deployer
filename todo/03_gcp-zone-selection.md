# Allow GCP Zone Selection

## Issue
GCP resources hard-code `${var.gcp_region}-a` for instances and disks. Regions without an `a` zone or machine types restricted to `b`/`c` fail immediately.

## Recommendation
Introduce a `gcp_zone` variable (defaulting to `<region>-a`, but overridable) or dynamically choose from available zones similar to the AWS AZ filtering logic.

## Next Steps
1. Extend `cmd_init`/README with the zone option
2. Update Terraform resources to consume it
3. Add validation/tests for unsupported zone-machine combinations