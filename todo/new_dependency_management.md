# Implement Centralized Dependency Checking

Add a centralized system to validate all required tools and their versions before running any exasol commands. This will provide better UX by failing early with clear error messages instead of cryptic "command not found" errors during deployment operations.

## Implementation Status (as of 2025-11-15)

**Current Status: NOT IMPLEMENTED**

Currently, there is **NO** generic tool/dependency checking across exasol commands. The codebase only has:
- ✅ Bash version check in main `exasol` script (Bash >= 4.0 required)
- ✅ Ad-hoc tool checking in `health` command only (`health_require_tool()`)
- ❌ No centralized dependency validation
- ❌ No version checking for required tools
- ❌ Commands fail with unclear errors when dependencies are missing

## Current Problems

### 1. Missing Dependency Checks
Commands like `deploy` and `destroy` directly invoke tools without checking if they're installed:
- `tofu` commands fail with "command not found" if OpenTofu/Terraform not installed
- `ansible-playbook` fails with unclear errors if Ansible not installed
- `jq` failures in lock/state management cause cryptic errors
- `ssh` failures in health checks are not caught early

### 2. No Version Validation
Even when tools are present, there's no check for minimum required versions:
- Terraform/OpenTofu >= 1.0 required (specified in `templates/terraform-*/main.tf`)
- Ansible version compatibility not checked
- Bash version only checked (>= 4.0)

### 3. Inconsistent Error Messages
Different commands handle missing tools differently:
- `health` command has its own `health_require_tool()` function
- Other commands just fail when the tool is invoked
- No consistent error message format

## Required Tools

### Critical (Required for Core Functionality)
1. **tofu** or **terraform** (>= 1.0)
   - Used by: `deploy`, `destroy`, `status`, `health` (optional)
   - Purpose: Infrastructure provisioning
   - Failure impact: Cannot deploy or destroy infrastructure

2. **ansible-playbook** (>= 2.9 recommended)
   - Used by: `deploy`
   - Purpose: Cluster configuration and Exasol setup
   - Failure impact: Infrastructure created but not configured

3. **jq** (>= 1.5)
   - Used by: `state.sh`, `lock` management throughout
   - Purpose: JSON parsing for state and lock files
   - Failure impact: State management fails, causing lock issues

4. **ssh** (any modern version)
   - Used by: `health`, Ansible internally
   - Purpose: Remote host connectivity checks
   - Failure impact: Health checks fail, Ansible may fail

### Important (Required for Full Functionality)
5. **curl** or **wget**
   - Used by: `init` command for downloading Exasol packages
   - Purpose: HTTP downloads
   - Failure impact: Cannot download Exasol DB and C4 packages

6. **awk**, **sed**, **grep** (standard versions)
   - Used by: `health` command IP update functions
   - Purpose: Text processing for configuration file updates
   - Failure impact: IP consistency updates fail
   - Note: Usually pre-installed on all Unix systems

### Optional (Cloud Provider Specific)
7. **aws** CLI (optional but recommended for AWS)
   - Used by: `health` command cloud metadata checks
   - Purpose: AWS instance validation
   - Failure impact: Cloud metadata checks skipped (graceful degradation)

8. **az** CLI (optional but recommended for Azure)
   - Used by: `health` command cloud metadata checks
   - Purpose: Azure VM validation
   - Failure impact: Cloud metadata checks skipped (graceful degradation)

9. **gcloud** CLI (optional but recommended for GCP)
   - Used by: `health` command cloud metadata checks
   - Purpose: GCP instance validation
   - Failure impact: Cloud metadata checks skipped (graceful degradation)

## Proposed Implementation

### Phase 1: Core Infrastructure (lib/common.sh)

Add these functions to `lib/common.sh`:

```bash
# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a command meets minimum version requirement
check_version() {
    local cmd="$1"
    local min_version="$2"
    local current_version="$3"

    # Use version comparison logic from lib/versions.sh
    if version_compare "$current_version" "$min_version"; then
        return 0
    else
        return 1
    fi
}

# Require a tool to be installed
require_tool() {
    local tool="$1"
    local purpose="${2:-required for exasol deployer}"

    if ! command_exists "$tool"; then
        log_error "Required tool '$tool' is not installed or not in PATH"
        log_error "Purpose: $purpose"
        log_error "Please install '$tool' and ensure it's in your PATH"
        return 1
    fi
    return 0
}

# Require a tool with minimum version
require_tool_version() {
    local tool="$1"
    local min_version="$2"
    local version_flag="${3:---version}"
    local purpose="${4:-required for exasol deployer}"

    if ! require_tool "$tool" "$purpose"; then
        return 1
    fi

    # Get current version
    local current_version
    current_version=$("$tool" "$version_flag" 2>&1 | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')

    if [[ -z "$current_version" ]]; then
        log_warn "Could not determine version of '$tool' - skipping version check"
        return 0
    fi

    if ! check_version "$tool" "$min_version" "$current_version"; then
        log_error "Tool '$tool' version $current_version is too old (minimum: $min_version)"
        log_error "Please upgrade '$tool' to version $min_version or newer"
        return 1
    fi

    log_debug "Tool '$tool' version $current_version OK (minimum: $min_version)"
    return 0
}

# Check all core dependencies
check_core_dependencies() {
    local all_ok=true

    log_debug "Checking core dependencies..."

    # Critical tools
    if ! require_tool "jq" "JSON parsing for state and lock management"; then
        all_ok=false
    fi

    if ! require_tool "ssh" "Remote host connectivity"; then
        all_ok=false
    fi

    # Check for either tofu or terraform
    if ! command_exists "tofu" && ! command_exists "terraform"; then
        log_error "Neither 'tofu' nor 'terraform' is installed"
        log_error "Please install OpenTofu (recommended) or Terraform >= 1.0"
        log_error "  OpenTofu: https://opentofu.org/docs/intro/install/"
        log_error "  Terraform: https://www.terraform.io/downloads"
        all_ok=false
    else
        local tf_cmd="tofu"
        command_exists "tofu" || tf_cmd="terraform"

        if ! require_tool_version "$tf_cmd" "1.0" "version" "Infrastructure provisioning"; then
            all_ok=false
        fi
    fi

    if ! require_tool "ansible-playbook" "Cluster configuration"; then
        all_ok=false
    fi

    # Check for curl or wget (at least one required)
    if ! command_exists "curl" && ! command_exists "wget"; then
        log_error "Neither 'curl' nor 'wget' is installed"
        log_error "At least one is required for downloading Exasol packages"
        log_error "Please install 'curl' or 'wget'"
        all_ok=false
    fi

    # Standard Unix tools (usually present, but check anyway)
    for tool in awk sed grep; do
        if ! command_exists "$tool"; then
            log_warn "Standard tool '$tool' not found - some features may not work"
        fi
    done

    if [[ "$all_ok" == "false" ]]; then
        return 1
    fi

    log_debug "All core dependencies OK"
    return 0
}

# Check optional cloud provider tools
check_cloud_dependencies() {
    local cloud_provider="${1:-}"

    case "$cloud_provider" in
        aws)
            if ! command_exists "aws"; then
                log_warn "AWS CLI not found - cloud metadata checks will be skipped"
                log_warn "Install with: pip install awscli"
            fi
            ;;
        azure)
            if ! command_exists "az"; then
                log_warn "Azure CLI not found - cloud metadata checks will be skipped"
                log_warn "Install with: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
            fi
            ;;
        gcp)
            if ! command_exists "gcloud"; then
                log_warn "Google Cloud SDK not found - cloud metadata checks will be skipped"
                log_warn "Install with: https://cloud.google.com/sdk/docs/install"
            fi
            ;;
    esac
}
```

### Phase 2: Integration with Main Script

Update `exasol` main script to check dependencies early:

```bash
# After sourcing libraries, before command routing:

# Check core dependencies (fail fast if missing)
if ! check_core_dependencies; then
    die "Missing required dependencies. Please install missing tools and try again."
fi

# For commands that need cloud provider tools, check after determining provider
# This can be done in cmd_init.sh, cmd_deploy.sh, etc.
```

### Phase 3: Command-Specific Checks

Each command can add its own specific checks:

**lib/cmd_init.sh:**
```bash
# In cmd_init()
# Check for download tools
if ! command_exists "curl" && ! command_exists "wget"; then
    die "Either curl or wget is required for downloading Exasol packages"
fi
```

**lib/cmd_deploy.sh:**
```bash
# In cmd_deploy()
# Check Terraform/Tofu
local tf_cmd="tofu"
command_exists "tofu" || tf_cmd="terraform"
require_tool "$tf_cmd" "Infrastructure provisioning"

# Check Ansible
require_tool "ansible-playbook" "Cluster configuration"
```

**lib/cmd_health.sh:**
```bash
# Replace health_require_tool() with centralized require_tool()
# The function already exists, just update calls:
require_tool "ssh" "Remote host connectivity checks"
```

## Implementation Checklist

### Phase 1: Core Infrastructure
- [ ] Add `command_exists()` to `lib/common.sh`
- [ ] Add `check_version()` to `lib/common.sh` (reuse logic from `lib/versions.sh`)
- [ ] Add `require_tool()` to `lib/common.sh`
- [ ] Add `require_tool_version()` to `lib/common.sh`
- [ ] Add `check_core_dependencies()` to `lib/common.sh`
- [ ] Add `check_cloud_dependencies()` to `lib/common.sh`

### Phase 2: Main Script Integration
- [ ] Call `check_core_dependencies()` in main `exasol` script before command routing
- [ ] Add dependency check to help output/documentation
- [ ] Handle failure gracefully with clear error messages

### Phase 3: Command-Specific Integration
- [ ] Update `lib/cmd_init.sh` to check for curl/wget
- [ ] Update `lib/cmd_deploy.sh` to check for tofu/terraform and ansible
- [ ] Update `lib/cmd_destroy.sh` to check for tofu/terraform
- [ ] Update `lib/cmd_health.sh` to use centralized `require_tool()` instead of `health_require_tool()`
- [ ] Add cloud provider CLI checks when provider is determined

### Phase 4: Testing
- [ ] Add unit tests for version comparison
- [ ] Add unit tests for dependency checking functions
- [ ] Test with missing dependencies to verify error messages
- [ ] Test with old tool versions to verify version checking
- [ ] Update E2E tests to verify dependency checks

### Phase 5: Documentation
- [ ] Update README with dependency requirements
- [ ] Add installation instructions for each required tool
- [ ] Document minimum version requirements
- [ ] Add troubleshooting section for dependency issues

## Benefits

1. **Better UX**: Clear error messages instead of cryptic failures
2. **Fail Fast**: Detect missing tools before starting long operations
3. **Version Safety**: Ensure tools meet minimum version requirements
4. **Consistent Errors**: All commands report missing tools the same way
5. **Documentation**: Dependency requirements clearly documented
6. **Easier Troubleshooting**: Users know exactly what to install

## Example Error Messages

### Before (Current State)
```bash
$ ./exasol deploy --deployment-dir ./my-deployment
...
bash: tofu: command not found
Terraform initialization failed
```

### After (Proposed)
```bash
$ ./exasol deploy --deployment-dir ./my-deployment
[ERROR] Required tool 'tofu' is not installed or not in PATH
[ERROR] Purpose: Infrastructure provisioning
[ERROR] Please install OpenTofu (recommended) or Terraform >= 1.0
[ERROR]   OpenTofu: https://opentofu.org/docs/intro/install/
[ERROR]   Terraform: https://www.terraform.io/downloads
[ERROR] Missing required dependencies. Please install missing tools and try again.
```

## Priority

**Medium Priority** - This is not blocking functionality but significantly improves UX and reduces user confusion. Should be implemented before 1.0 release.

## Success Criteria

- ✅ All required tools are checked before running any command
- ✅ Version requirements are validated for critical tools
- ✅ Clear, actionable error messages when dependencies are missing
- ✅ No more cryptic "command not found" errors during operations
- ✅ Consistent dependency checking across all commands
- ✅ Documentation clearly lists all requirements