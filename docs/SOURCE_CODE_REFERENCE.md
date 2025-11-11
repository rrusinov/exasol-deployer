# Exasol Go Source Code - File Reference Guide

## Source Code Directory Structure

```
reference/personal-edition-source-code/
├── cmd/exasol/                    # Main CLI commands
│   ├── main.go                    # Entry point
│   ├── root.go                    # Root command, logging setup
│   ├── init.go                    # Init command implementation
│   ├── deploy.go                  # Deploy command
│   ├── destroy.go                 # Destroy command
│   ├── status.go                  # Status command
│   ├── connect.go                 # Connect command
│   ├── info.go                    # Info/diagnostics
│   ├── shell.go                   # Interactive shell
│   ├── version.go                 # Version info
│   ├── deploymentControl.go       # Deployment control utils
│   └── util.go                    # CLI utilities
│
├── internal/
│   ├── config/                    # Configuration management
│   │   ├── config.go              # Generic read/write config (JSON/YAML)
│   │   ├── paths.go               # Path constants (tofu, vars, state, etc)
│   │   ├── workflow_state.go      # Workflow state machine (initialized, failed, success)
│   │   ├── deployment_lock.go     # File-based locking for concurrency
│   │   ├── exasol_config.go       # Post-deploy scripts configuration
│   │   ├── node_details.go        # Node/infrastructure details from terraform
│   │   └── secrets.go             # Secrets file management
│   │
│   ├── deploy/                    # Deployment orchestration
│   │   ├── init.go                # InitTofu() function - main init logic
│   │   ├── deploy.go              # Deploy() & DeployTofu() functions
│   │   ├── destroy.go             # Destroy() function
│   │   ├── status.go              # Status() function & state machine logic
│   │   ├── shared.go              # WithDeploymentLock() - lock management
│   │   ├── connect.go             # Database connection
│   │   ├── deploymentControl.go   # Control utilities
│   │   ├── shell.go               # Interactive shell
│   │   └── script_runner.go       # Post-deploy script execution
│   │
│   ├── util/                      # Utilities
│   │   └── util.go                # File operations, logging
│   │
│   ├── tofu/                      # OpenTofu execution
│   │   └── *.go                   # Terraform/OpenTofu runner
│   │
│   ├── remote/                    # Remote execution via SSH
│   │   └── *.go                   # SSH connection & execution
│   │
│   └── connect/                   # Database connectivity
│       └── *.go                   # Exasol driver integration
│
├── assets/                        # Embedded assets
│   ├── tofu_config/
│   │   ├── aws/                   # AWS Terraform templates
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   └── [other providers]/
│   │
│   └── binaries/                  # Platform-specific tofu binaries
│       ├── tofu-linux-amd64
│       ├── tofu-linux-arm64
│       ├── tofu-darwin-amd64
│       ├── tofu-darwin-arm64
│       └── tofu-windows-*.exe
│
└── doc/
    ├── architecture.md            # High-level architecture & design
    ├── development.md             # Development guide
    ├── glossary.md                # Terminology
    └── [other docs]
```

---

## Key Source Files for Bash Implementation Reference

### 1. Init Command Implementation

**Files to Study:**
- `/reference/personal-edition-source-code/cmd/exasol/init.go` - CLI layer
  - How CLI flags are registered dynamically
  - How variables are collected from user input
  - Error handling for unknown variables

- `/reference/personal-edition-source-code/internal/deploy/init.go` - Core logic
  - Deployment directory validation (must be empty)
  - Asset extraction (terraform files, binary)
  - Variable validation
  - Workflow state initialization

**Key Functions:**
- `InitTofu()` - Main init orchestration
- `writeAssets()` - Extract and write configuration files
- `registerDeploymentTypes()` - Dynamic command registration

**Critical Validations:**
```
1. Check directory is empty
2. Verify all provided variables are known
3. Create required directory structure
4. Write workflow state file
```

### 2. Configuration Files

**Configuration Read/Write Logic:**
- `/reference/personal-edition-source-code/internal/config/config.go`
  - `readConfig[T]()` - Generic JSON/YAML reader
  - `writeConfig()` - Generic JSON/YAML writer
  - Format detection by file extension

**State Machine Definition:**
- `/reference/personal-edition-source-code/internal/config/workflow_state.go`
  - Union-based state: initialized, deploymentFailed, deploymentSuccessful
  - Read/write functions for state persistence

**Locking Mechanism:**
- `/reference/personal-edition-source-code/internal/config/deployment_lock.go`
  - `AcquireDeploymentLock()` - Non-blocking lock
  - `ReleaseDeploymentLock()` - Remove lock

**Path Management:**
- `/reference/personal-edition-source-code/internal/config/paths.go`
  - All relative path definitions
  - Binary name, config dir, variable file name, plan file path

### 3. Status Tracking

**Status Command:**
- `/reference/personal-edition-source-code/cmd/exasol/status.go`
  - Cobra command definition

**Status Logic:**
- `/reference/personal-edition-source-code/internal/deploy/status.go`
  - Lock-based progress detection
  - Workflow state reading
  - Database connection verification
  - JSON output formatting

**Status States:**
```
- "initialized" - Ready to deploy
- "deployment_in_progress" - Lock file exists
- "deployment_failed" - Post-deploy script failed
- "database_connection_failed" - DB not responding
- "database_ready" - All systems operational
```

### 4. Deployment Lifecycle

**Deploy Orchestration:**
- `/reference/personal-edition-source-code/internal/deploy/deploy.go`
  - `Deploy()` - Main deploy function
  - `DeployTofu()` - Infrastructure provisioning
  - `RunPostDeployScripts()` - SSH script execution
  - Lock-based concurrency control

**Destroy Operation:**
- `/reference/personal-edition-source-code/internal/deploy/destroy.go`
  - Resource cleanup
  - State reset to "initialized"

**Lock Management:**
- `/reference/personal-edition-source-code/internal/deploy/shared.go`
  - `WithDeploymentLock()` - Lock wrapper pattern

### 5. Data Structures

**Node Details** (created by terraform):
- `/reference/personal-edition-source-code/internal/config/node_details.go`
  - Cluster metadata
  - Node information (IP, DNS, SSH details)
  - Database connection info
  - TLS certificate

**Secrets Management:**
- `/reference/personal-edition-source-code/internal/config/secrets.go`
  - Password generation
  - Secret file location via glob pattern

**Exasol Configuration:**
- `/reference/personal-edition-source-code/internal/config/exasol_config.go`
  - Post-deployment scripts list
  - Script execution parameters

### 6. Utilities and Helpers

**File Operations:**
- `/reference/personal-edition-source-code/internal/util/util.go`
  - `EnsureDir()` - Create directory with proper permissions
  - `ListDir()` - List directory contents
  - `AbsPathNoFail()` - Safe absolute path conversion
  - `LoggedError()` - Error logging and wrapping

**CLI Utilities:**
- `/reference/personal-edition-source-code/cmd/exasol/util.go`
  - Flag parsing helpers
  - Output formatting

---

## Important Constants and Configuration Values

### From paths.go
```go
TofuBinaryPath() = "tofu"              // or "tofu.exe" on Windows
TofuConfigDir() = ""                   // Root of deployment dir
PlanFilePath() = "plan.tfplan"
TfVarsFileName() = "vars.tfvars"
```

### From workflow_state.go
```
workflowStateFileName = ".workflowState.json"
```

### From deployment_lock.go
```
deploymentLockFileName = ".exasolLock.json"
```

### From node_details.go
```
nodeDetailsGlob = "deployment-exasol-*.json"
```

### From secrets.go
```
secretsGlob = "secrets-exasol-*.json"
```

### From exasol_config.go
```
exasolConfigFileName = "exasolConfig.yaml"
```

---

## Error Types Referenced in Code

### In deploy/init.go
```
ErrUnknownVariable
ErrDeploymentDirectoryNotEmpty
```

### In config/config.go
```
ErrNoFileMatchedGlobPattern
ErrMissingConfigFile
```

### In deploy/status.go
```
StatusInitialized
StatusDeploymentInProgress
StatusDeploymentFailed
StatusDatabaseConnectionFailed
StatusDatabaseReady
```

### In deploy/deploy.go
```
ErrUnexpectedDeploymentStatus
ErrNoMatchingNodesFound
```

### In deploy/shared.go
```
ErrUnknownDeploymentType
ErrFailedToLockDeployment
```

### In config/node_details.go
```
ErrNoNodeDetailsFile
ErrUnknownNodeName
```

---

## Command Hierarchy

```
exasol (root)
├── init [deployment-type] (aws is default)
│   ├── init aws
│   ├── init azure
│   └── init [other-providers]
├── deploy
├── destroy
├── status
├── connect
├── info
├── shell
├── version
└── [other commands]
```

---

## Testing and Examples

### Test Files Available
- `/reference/personal-edition-source-code/internal/deploy/script_runner_test.go`
  - Examples of how script execution is tested
  - Mock implementations

### Documentation
- `/reference/personal-edition-source-code/doc/architecture.md` - High-level design
- `/reference/personal-edition-source-code/README.md` - User guide
- `/reference/personal-edition-source-code/CONTRIBUTING.md` - Development guide
- `/reference/personal-edition-source-code/assets/tofu_config/aws/README.md` - AWS specifics

---

## Key Patterns to Implement in Bash

Based on the source code structure, prioritize these patterns:

1. **Workflow State Machine** (workflow_state.go)
   - Implement as JSON union types
   - Clear state transitions
   - State validation before operations

2. **File-Based Locking** (deployment_lock.go)
   - Non-blocking lock acquisition
   - Timestamp-based lock ownership

3. **Configuration Management** (config.go)
   - Generic read/write for JSON and YAML
   - Proper file permissions (0600)
   - Format detection by extension

4. **Path Resolution** (paths.go)
   - Consistent path definitions
   - Relative to deployment directory
   - Platform-specific considerations

5. **Deployment Directory Isolation**
   - Empty directory validation
   - Self-contained artifacts
   - Glob pattern file discovery

6. **Error Handling** (util.go)
   - Contextual error messages
   - Logged errors with details
   - Clear error types

7. **Directory Operations** (util.go)
   - Proper permission handling (0750 for dirs, 0600 for secrets)
   - Safe directory creation
   - Directory listing and validation

---

## Reference Implementation Notes

The Go implementation provides excellent patterns for bash:

- **Strong typing** becomes validation patterns in bash
- **Structured logging** becomes error messages and debug output
- **Error wrapping** becomes multi-level error reporting
- **Concurrency control** becomes file-based locking
- **Configuration serialization** becomes JSON/YAML read/write

The most important learning: **Use explicit state files and validation checks** rather than implicit state in script execution.

