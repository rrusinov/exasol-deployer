# Library Modules

Core shell library modules for the Exasol Deployer CLI.

## Contents

- `common.sh` - Core utilities (logging, colors, validation, error handling)
- `state.sh` - Deployment state management and file locking
- `versions.sh` - Database version parsing and validation
- `cmd_init.sh` - Initialization command implementation
- `cmd_deploy.sh` - Deployment command implementation
- `cmd_start.sh` - Start command implementation
- `cmd_stop.sh` - Stop command implementation
- `cmd_destroy.sh` - Destroy command implementation
- `cmd_status.sh` - Status command implementation
- `cmd_health.sh` - Health check command implementation
- `health_internal.sh` - Internal health check functions
- `progress_tracker.sh` - Progress tracking and reporting
- `progress_keywords.sh` - Progress keyword definitions
- `permissions/` - Cloud provider permission definitions

## Usage

Library modules are sourced by the main `exasol` CLI script:

```bash
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/cmd_init.sh"
```

## Code Style

All library modules follow these conventions:

- Include guards to prevent double-sourcing
- `readonly` for constants (UPPER_CASE)
- `snake_case` for functions and variables
- Error handling via `die` function from common.sh
- Comprehensive inline documentation
