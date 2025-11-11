# Exasol Personal Edition - Go Source Code Analysis

## Executive Summary

The Exasol Personal Edition deployment tool is a well-architected Go application that orchestrates cloud infrastructure provisioning and database installation. A bash script implementation should follow these core patterns: filesystem-based state management, structured JSON/YAML configuration, deployment directory isolation, workflow state tracking, and file locking for concurrency control.

---

## 1. Init Command Workflow

### How It Works

The `init` command prepares a deployment directory for infrastructure provisioning:

#### Command Flow (cmd/exasol/init.go)
- User runs: `exasol init [deployment-type] --flag=value`
- Dynamically registers deployment type subcommands (aws, azure, etc.)
- Each subcommand:
  - Extracts deployment info (variable definitions)
  - Creates CLI flags from deployment variables
  - Marks required vs. optional variables
  - Calls `deploy.InitTofu()` with user-provided variables

#### Core Initialization Logic (internal/deploy/init.go)

```go
func InitTofu(context, deploymentType, deploymentDir, vars) error:
  1. Check deployment directory is EMPTY
  2. Write assets to deployment directory:
     - Terraform/OpenTofu configuration files
     - Platform-specific OpenTofu binary
  3. Create vars.tfvars file with user-provided variables
  4. Write workflow state file (.workflowState.json)
  5. Return success
```

### Files/Structure Created by Init

After `exasol init aws`, the deployment directory contains:

```
deployment-dir/
├── .workflowState.json          # Workflow state (initialized)
├── vars.tfvars                  # Terraform variables (HCL format)
├── plan.tfplan                  # Terraform plan file (created during deploy)
├── tofu                         # OpenTofu binary (platform-specific)
├── .exasolLock.json             # Lock file during operations
├── *.tf                         # Terraform configuration files (main, variables, outputs)
├── terraform.tfstate            # Terraform state (created during deploy)
├── exasolConfig.yaml            # Exasol config (post-deploy scripts)
├── deployment-exasol-*.json     # Node details (created by terraform)
├── secrets-exasol-*.json        # Secrets: passwords, SSH key paths (created by terraform)
└── <deployment-id>.pem          # SSH private key file
```

### Key Validation

- **Pre-flight Check**: Deployment directory MUST be empty
  - Prevents accidental re-initialization
  - Error: `ErrDeploymentDirectoryNotEmpty`
- **Variable Validation**: Unknown variables rejected
  - Each flag maps to a known Terraform variable
  - Error: `ErrUnknownVariable`

---

## 2. Configuration Storage and Management

### Configuration Architecture

#### Two-Tier Configuration System

**Tier 1: User-Facing Configuration (Variables)**
- Collected via CLI flags during `init`
- Stored in `vars.tfvars` (HCL format for Terraform)
- Examples: instance_type, region, cluster_size, etc.

**Tier 2: System Configuration Files (JSON)**
- Workflow state tracking
- Node/infrastructure details
- Secrets and credentials
- Structured as JSON with strong typing

### Key Configuration Files

#### 1. Workflow State (.workflowState.json)

Union-based state machine with possible states:

```json
{
  "initialized": {},
  "deploymentFailed": {"error": "failure message"},
  "deploymentSuccessful": {}
}
```

**States and Transitions:**
```
init:
  -> WriteWorkflowState(initialized)

deploy:
  requires: state == initialized
  on success -> WriteWorkflowState(deploymentSuccessful)
  on post-script failure -> WriteWorkflowState(deploymentFailed)

destroy:
  returns to: WriteWorkflowState(initialized)
  
status:
  reads current state
  may attempt DB connection verification
```

**Go Types** (internal/config/workflow_state.go):
```go
type WorkflowStateInitialized struct{}
type WorkflowStateDeploymentFailed struct{ Error string }
type WorkflowStateDeploymentSuccessful struct{}
```

#### 2. Deployment Lock (.exasolLock.json)

Prevents concurrent operations:

```json
{
  "time": "2024-01-15T10:30:00Z"
}
```

**Locking Pattern:**
```
AcquireDeploymentLock(dir):
  if .exasolLock.json exists:
    return false (already locked)
  else:
    create .exasolLock.json with timestamp
    return true (lock acquired)

ReleaseDeploymentLock(dir):
  delete .exasolLock.json
```

#### 3. Node Details (deployment-exasol-{id}.json)

Created by Terraform, contains infrastructure info:

```json
{
  "deploymentId": "unique-id",
  "region": "us-west-2",
  "availabilityZone": "us-west-2a",
  "clusterSize": 1,
  "instanceType": "t3.medium",
  "vpcId": "vpc-xxx",
  "subnetId": "subnet-xxx",
  "nodes": {
    "n11": {
      "availabilityZone": "us-west-2a",
      "dnsName": "ec2-54-xxx.compute-1.amazonaws.com",
      "instanceId": "i-0xxx",
      "publicIp": "54.xxx.xxx.xxx",
      "privateIp": "10.x.x.x",
      "ssh": {
        "command": "ssh -i key.pem ec2-user@host",
        "keyFile": "deployment-id.pem",
        "keyName": "deployment-key-id",
        "port": "22",
        "username": "ec2-user"
      },
      "tlsCert": "-----BEGIN CERTIFICATE-----...",
      "database": {
        "dbPort": "8563",
        "uiPort": "8443",
        "url": "jdbc:exa:54.xxx.xxx.xxx:8563"
      }
    }
  }
}
```

#### 4. Secrets (secrets-exasol-{id}.json)

Generated passwords and credentials:

```json
{
  "dbPassword": "GeneratedPassword123!",
  "adminUiPassword": "GeneratedPassword456!"
}
```

**File Permissions**: Created with 0600 (owner read/write only)

#### 5. Exasol Configuration (exasolConfig.yaml)

Post-deployment scripts configuration:

```yaml
postDeployScripts:
  - node: "n11"          # Node glob pattern (wildcard support)
    filename: "script.sh" # Script path relative to deployment dir
    executeInParallel: false
    silent: false
```

### Configuration System Patterns

#### Generic Read/Write Functions (internal/config/config.go)

```go
func readConfig[T](path, name) (*T, error):
  - Opens file at path
  - Detects format by extension (.json or .yaml)
  - Decodes using appropriate decoder
  - Returns typed struct

func writeConfig(config, path, name) error:
  - Creates/truncates file at path
  - Sets permissions to 0600 for sensitive files
  - Encodes using appropriate encoder (.json or .yaml)
  - Returns error if any step fails
```

#### Error Handling

- `ErrMissingConfigFile`: File doesn't exist
- `ErrNoFileMatchedGlobPattern`: Glob pattern found no files
- Structured error returns with context for debugging

---

## 3. Deployment Directory Structure

### Overall Layout

```
deployment-dir/                      # Self-contained deployment
│
├── Configuration & State
│   ├── .workflowState.json          # Current workflow state
│   ├── .exasolLock.json             # Lock file (during operations)
│   ├── vars.tfvars                  # Terraform variables
│   ├── exasolConfig.yaml            # Post-deploy scripts config
│   └── terraform.tfstate            # Terraform state (created during deploy)
│
├── Infrastructure-as-Code
│   ├── tofu                         # OpenTofu binary (extracted during init)
│   ├── main.tf                      # Terraform main configuration
│   ├── variables.tf                 # Terraform variable definitions
│   ├── outputs.tf                   # Terraform outputs
│   └── *.tf                         # Additional Terraform files (provider-specific)
│
├── Deployment Outputs
│   ├── deployment-exasol-{id}.json  # Node details (created by terraform)
│   ├── {id}.pem                     # SSH private key
│   ├── secrets-exasol-{id}.json     # Secrets (created by terraform)
│   └── plan.tfplan                  # Terraform plan file
│
└── Post-Deployment
    ├── post_deployment/
    │   └── *.sh                     # Installation scripts
    └── logs/                         # Optional script execution logs
```

### Directory Isolation

- **One deployment per directory**: Critical constraint
- **Portable**: Self-contained, can be copied to another machine
- **Version control**: Should NOT be committed (contains secrets)
- **Cleanup**: Directory should be preserved until destruction (contains state)

### Path Resolution

All paths in code are relative to deployment directory:
- `TofuConfigDir()` returns "" (root of deployment dir)
- `TfVarsFileName()` returns "vars.tfvars"
- `PlanFilePath()` returns "plan.tfplan"
- `TofuBinaryPath()` returns "tofu" (or "tofu.exe" on Windows)

---

## 4. Status Tracking and Reporting

### Status Command Flow

```
exasol status [--deployment-dir DIR]
  ↓
deploy.Status(ctx, deploymentDir)
  ↓
1. Try to acquire deployment lock
   - If locked: return { status: "deployment_in_progress" }
   - If not locked: release it and proceed
  ↓
2. Read .workflowState.json
  ↓
3. Match workflow state:
   ├─ WorkflowStateInitialized
   │  └─> return { status: "initialized", message: "Ready for deployment" }
   │
   ├─ WorkflowStateDeploymentFailed
   │  └─> return { status: "deployment_failed", error: "..." }
   │
   └─ WorkflowStateDeploymentSuccessful
      ├─ Attempt database connection
      ├─ If connection succeeds (invalid credentials = success signal):
      │  └─> return { status: "database_ready", message: "..." }
      └─ If connection fails:
         └─> return { status: "database_connection_failed", error: "..." }
  ↓
4. Output JSON to stdout
```

### Status Output Structure

```json
{
  "status": "database_ready|deployment_in_progress|initialized|deployment_failed|database_connection_failed",
  "message": "optional descriptive message",
  "error": "optional error details"
}
```

### Possible Status Values

| Status | Meaning | Next Action |
|--------|---------|-------------|
| `initialized` | Directory prepared, ready to deploy | Run `deploy` |
| `deployment_in_progress` | Lock file exists, operation in progress | Wait and retry |
| `deployment_failed` | Deploy/post-script failed | Review error, run `destroy`, retry |
| `database_connection_failed` | Infrastructure ready but DB unavailable | Check logs, retry |
| `database_ready` | Database running and accepting connections | Run `connect` |

### Lock-Based Status Detection

The lock file serves dual purposes:
1. **Mutual exclusion**: Prevents concurrent operations
2. **Status indication**: Presence indicates in-progress operation
   - If lock exists: Status = "deployment_in_progress"
   - If lock doesn't exist: Proceed with status check

---

## 5. Version Management and Configuration Patterns

### Version Tracking

**No explicit versioning in deployment state**, but:
- OpenTofu binary is platform-specific and version-pinned
- Terraform templates are stored with each deployment
- State files track infrastructure state independently

### Deployment Lifecycle Patterns

#### State Machine Implementation

The application uses explicit state management with strong typing:

```
Init Command:
  deploymentDir
    ├─ Must be empty
    ├─ Extract tofu binary, terraform files
    └─ Write .workflowState.json with initialized state

Deploy Command:
  Requires: state == initialized
  ├─ Acquire lock (.exasolLock.json)
  ├─ Run tofu init, plan, apply
  ├─ Run post-deploy scripts via SSH
  ├─ Write state = deploymentSuccessful OR deploymentFailed
  └─ Release lock

Destroy Command:
  ├─ Acquire lock
  ├─ Run tofu destroy
  ├─ Write state = initialized (allows re-deploy)
  └─ Release lock

Status Command:
  ├─ Check lock (indicates in-progress)
  └─ Read and report current state
```

#### Error Recovery

**On Deploy Failure:**
1. If tofu apply fails: Can retry `deploy` (state still = initialized)
2. If post-deploy script fails: Must run `destroy` first (state = deploymentFailed)
3. If destroy partially fails: User can manually cleanup and reinit

**State Preservation:** Failed operations keep state files for debugging

### Concurrency Control Pattern

```
WithDeploymentLock(dir, func) error:
  1. Call AcquireDeploymentLock(dir)
     - Creates .exasolLock.json if doesn't exist
     - Returns false if already locked (non-blocking)
  2. If lock acquired:
     - Execute provided function
     - Always release lock in defer()
  3. Return error if lock not acquired or function fails
```

Benefits:
- Simple file-based locking (no external daemon)
- Works across file systems and over NFS
- Clear ownership via timestamp in lock file
- Non-blocking (returns immediately if locked)

### Configuration Validation Patterns

#### CLI Flag to Terraform Variable Mapping

```
CLI Layer (cobra):
  ├─ Query deployment info for available variables
  ├─ Create flags for each variable
  ├─ Mark required variables with cobra.MarkFlagRequired()
  └─ Collect values from user

Validation Layer:
  ├─ Verify all variables provided are known
  ├─ Check required variables are set
  └─ Type conversion (string -> number for numeric vars)

Storage Layer:
  └─ Write to vars.tfvars (Terraform will validate on execution)
```

### Deployment Type Registration Pattern

```
registerDeploymentTypes():
  ├─ Call deploy.ListDeploymentTypes()
  │  └─ Returns array from assets package (embedded in binary)
  ├─ For each deployment type:
  │  ├─ Check if already registered
  │  ├─ Create new cobra command
  │  └─ Call configureTofuCommand()
  └─ Add command to initCmd

configureTofuCommand(cmd, deploymentName):
  ├─ Get deployment info (variables, descriptions)
  ├─ For each variable:
  │  ├─ Create CLI flag (--var-name)
  │  ├─ Set description and default value
  │  └─ Mark as required if needed
  └─ Set command.RunE to call deploy.InitTofu()
```

This pattern allows:
- Dynamic registration of new deployment types (just add assets)
- Consistent CLI interface across all deployment types
- Strong typing through Go's type system

---

## Key Design Patterns for Bash Implementation

### 1. State Machine Pattern

Implement explicit state through files:
```bash
# Instead of implicit state, store explicitly
STATE_INITIALIZED="initialized"
STATE_DEPLOYMENT_IN_PROGRESS="deployment_in_progress"
STATE_DEPLOYMENT_FAILED="deployment_failed"
STATE_DATABASE_READY="database_ready"

read_workflow_state() {
    local state_file="$deployment_dir/.workflowState.json"
    jq -r '.initialized // .deploymentFailed // .deploymentSuccessful' "$state_file"
}

write_workflow_state() {
    local state="$1"
    local state_file="$deployment_dir/.workflowState.json"
    case "$state" in
        initialized)
            echo '{"initialized": {}}' > "$state_file"
            ;;
        deploymentFailed)
            local error="$2"
            echo "{\"deploymentFailed\": {\"error\": \"$error\"}}" > "$state_file"
            ;;
        deploymentSuccessful)
            echo '{"deploymentSuccessful": {}}' > "$state_file"
            ;;
    esac
}
```

### 2. File-Based Locking Pattern

```bash
LOCK_FILE="$deployment_dir/.exasolLock.json"

acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        return 1  # Already locked
    fi
    echo "{\"time\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$LOCK_FILE"
    return 0
}

release_lock() {
    rm -f "$LOCK_FILE"
}

with_deployment_lock() {
    local func="$1"
    if ! acquire_lock; then
        echo "Deployment is currently in progress" >&2
        return 1
    fi
    trap release_lock EXIT
    $func
}
```

### 3. Configuration Path Resolution Pattern

```bash
# Define paths relative to deployment directory
tofu_binary_path() { echo "tofu"; }
tf_vars_file_name() { echo "vars.tfvars"; }
plan_file_path() { echo "plan.tfplan"; }
tofu_config_dir() { echo "."; }  # root of deployment dir
workflow_state_file() { echo ".workflowState.json"; }
lock_file_path() { echo ".exasolLock.json"; }

# Use with deployment directory
get_path() {
    local deployment_dir="$1"
    local path_func="$2"
    echo "$deployment_dir/$($path_func)"
}
```

### 4. Glob Pattern Resolution Pattern

```bash
# Find files matching glob pattern
find_glob() {
    local dir="$1"
    local pattern="$2"
    local matches
    mapfile -t matches < <(find "$dir" -maxdepth 1 -name "$pattern" 2>/dev/null)
    
    if [ ${#matches[@]} -eq 0 ]; then
        echo "Error: no file matched pattern \"$pattern\"" >&2
        return 1
    fi
    echo "${matches[0]}"
}

# Usage
secrets_file=$(find_glob "$deployment_dir" "secrets-exasol-*.json")
node_details=$(find_glob "$deployment_dir" "deployment-exasol-*.json")
```

### 5. JSON Configuration Read/Write Pattern

```bash
read_json_config() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "Error: config file not found: $path" >&2
        return 1
    fi
    cat "$path" | jq .
}

write_json_config() {
    local path="$1"
    local data="$2"
    local permissions="${3:-0600}"
    
    echo "$data" | jq . > "$path"
    chmod "$permissions" "$path"
}

read_yaml_config() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "Error: config file not found: $path" >&2
        return 1
    fi
    # Use yq if available, or parse manually
    cat "$path"
}
```

### 6. Deployment Directory Validation Pattern

```bash
validate_deployment_dir() {
    local deployment_dir="$1"
    local max_entries="$2"
    
    # Create if doesn't exist
    mkdir -p "$deployment_dir"
    
    # Check if empty
    local count
    count=$(find "$deployment_dir" -maxdepth 1 -type f | wc -l)
    
    if [ "$count" -gt 0 ]; then
        echo "Error: deployment directory not empty" >&2
        find "$deployment_dir" -maxdepth 1 -type f | head -1
        return 1
    fi
}

ensure_dir() {
    local path="$1"
    if [ -f "$path" ]; then
        echo "Error: path is not a directory: $path" >&2
        return 1
    fi
    mkdir -p "$path"
}
```

### 7. Variable Validation Pattern

```bash
# Define available variables with metadata
declare -A VARIABLES=(
    [instance_type]="t3.medium"
    [region]="us-west-2"
    [cluster_size]="1"
)

declare -A REQUIRED=(
    [instance_type]="true"
    [region]="false"  # has default
)

# Validate and collect variables
validate_variables() {
    local -n var_dict=$1  # passed by reference
    
    for var in "${!var_dict[@]}"; do
        if [ -z "${VARIABLES[$var]+x}" ]; then
            echo "Error: unknown variable: $var" >&2
            return 1
        fi
    done
}

# Create vars.tfvars from collected variables
write_vars_tfvars() {
    local deployment_dir="$1"
    local -n vars=$2
    local output_file="$deployment_dir/vars.tfvars"
    
    {
        for var in "${!vars[@]}"; do
            echo "$var = \"${vars[$var]}\""
        done
    } > "$output_file"
}
```

---

## Summary for Bash Implementation

### Core Components to Implement

1. **Init Command**
   - Validate deployment directory is empty
   - Extract assets (terraform files, binary)
   - Collect configuration variables via CLI flags
   - Write vars.tfvars with proper formatting
   - Write initial workflow state (initialized)

2. **State Management**
   - JSON files for workflow state (.workflowState.json)
   - File-based locking (.exasolLock.json)
   - Read/write JSON and YAML with proper permissions

3. **Deployment Directory Structure**
   - Follow Go implementation's path conventions
   - Store all artifacts relative to deployment directory
   - Use glob patterns for dynamic file discovery

4. **Status Command**
   - Check lock file for in-progress indication
   - Read workflow state from JSON
   - Report status with appropriate message

5. **Error Handling**
   - Validate pre-conditions before operations
   - Preserve state on failures
   - Provide context in error messages

### Critical Success Factors

- **State isolation**: Each deployment directory is independent
- **Atomic operations**: Use locking to prevent concurrent modifications
- **Clear state machine**: Explicit states with well-defined transitions
- **Portable artifacts**: Self-contained directory with all needed files
- **Error recovery**: Failed states should be debuggable and recoverable
- **Configuration flexibility**: Variable system should be extensible

