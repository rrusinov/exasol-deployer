# Guard DigitalOcean Architecture Mismatches

## Issue
The DO template always uses the x86 image slug even though `instance_architecture` accepts `arm64`, and the CLI does not stop users from initializing an arm64 deployment on DigitalOcean.

## Recommendation
Until DO offers arm droplets, reject arm64 versions during `exasol init` for this provider (or add conditional logic that maps to the correct image/size once available).

## Next Steps
1. Add a validation hook in `cmd_init`
2. Document the limitation in `README.md`
3. Extend tests to cover the refusal path