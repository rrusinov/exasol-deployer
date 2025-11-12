# Progress Output Documentation

## Overview

The Exasol deployer emits machine-parsable progress information in JSON format to multiple destinations:
- **stdout** - Real-time JSON events for piping to other tools
- **stderr** - Human-readable colored output with emojis
- **`.exasol-progress.jsonl`** - JSON Lines file in the deployment directory (persistent log)

This allows UIs and automation tools to track the progress of operations in real-time.

## Output Format

### JSON Progress Events (stdout)

Each progress event is emitted as a single-line JSON object with the following structure:

```json
{
  "timestamp": "2025-11-12T10:30:45Z",
  "stage": "init|deploy|destroy",
  "step": "step_name",
  "status": "started|in_progress|completed|failed",
  "message": "Human-readable description",
  "percent": 75,
  "overall_percent": 42
}
```

### Fields

- **timestamp**: ISO 8601 UTC timestamp (e.g., `2025-11-12T10:30:45Z`)
- **stage**: The high-level operation being performed
  - `init` - Initializing a new deployment
  - `deploy` - Deploying infrastructure and database
  - `destroy` - Destroying infrastructure and cleaning up
- **step**: Specific step within the stage (see step lists below)
- **status**: Current status of the step
  - `started` - Step has just begun
  - `in_progress` - Step is actively running (may include percentage)
  - `completed` - Step finished successfully
  - `failed` - Step encountered an error
- **message**: Human-readable description of what's happening
- **percent**: (Optional) Completion percentage for the current step (0-100)
- **overall_percent**: Overall completion percentage across the entire stage (0-100), calculated from weighted step completion

### Human-Readable Output (stderr)

Colored, emoji-enriched messages are written to stderr:
- ▶ Step started
- ⏳ Step in progress
- ✅ Step completed
- ❌ Step failed

## Stage-Specific Steps

### Init Stage

| Step | Description |
|------|-------------|
| `validate_config` | Validating configuration and parameters |
| `create_directories` | Creating deployment directory structure |
| `initialize_state` | Initializing `.exasol.json` state file |
| `copy_templates` | Copying Terraform and Ansible templates |
| `generate_variables` | Creating `variables.auto.tfvars` file |
| `store_credentials` | Storing credentials in `.credentials.json` |
| `generate_readme` | Creating deployment-specific README |
| `complete` | Initialization finished |

### Deploy Stage

| Step | Description | Progress Tracking |
|------|-------------|-------------------|
| `begin` | Starting deployment process | No percentage |
| `tofu_init` | Initializing OpenTofu (Terraform) | No percentage |
| `tofu_plan` | Planning infrastructure changes | No percentage |
| `tofu_apply` | Creating cloud infrastructure | **Yes - percentage based on resources created** |
| `wait_instances` | Waiting for instances to initialize (60s) | No percentage |
| `ansible_config` | Configuring cluster with Ansible | **Yes - percentage based on tasks completed** |
| `complete` | Deployment finished | 100% |

### Destroy Stage

| Step | Description | Progress Tracking |
|------|-------------|-------------------|
| `begin` | Starting destruction process | No percentage |
| `confirm` | Waiting for user confirmation (if not auto-approved) | No percentage |
| `tofu_destroy` | Destroying cloud infrastructure | **Yes - percentage based on resources destroyed** |
| `cleanup` | Cleaning up deployment files | No percentage |
| `complete` | Destruction finished | 100% |

## Example Progress Sequence

### Successful Init

```json
{"timestamp":"2025-11-12T10:30:01Z","stage":"init","step":"validate_config","status":"started","message":"Initializing deployment directory: /path/to/deploy"}
{"timestamp":"2025-11-12T10:30:02Z","stage":"init","step":"validate_config","status":"completed","message":"Configuration validated","percent":100}
{"timestamp":"2025-11-12T10:30:02Z","stage":"init","step":"create_directories","status":"started","message":"Creating deployment directories"}
{"timestamp":"2025-11-12T10:30:02Z","stage":"init","step":"create_directories","status":"completed","message":"Deployment directories created","percent":100}
{"timestamp":"2025-11-12T10:30:02Z","stage":"init","step":"initialize_state","status":"started","message":"Initializing deployment state"}
{"timestamp":"2025-11-12T10:30:03Z","stage":"init","step":"initialize_state","status":"completed","message":"Deployment state initialized","percent":100}
{"timestamp":"2025-11-12T10:30:03Z","stage":"init","step":"copy_templates","status":"started","message":"Copying deployment templates for aws"}
{"timestamp":"2025-11-12T10:30:04Z","stage":"init","step":"copy_templates","status":"completed","message":"Templates copied successfully","percent":100}
{"timestamp":"2025-11-12T10:30:04Z","stage":"init","step":"generate_variables","status":"started","message":"Creating Terraform variables file"}
{"timestamp":"2025-11-12T10:30:05Z","stage":"init","step":"generate_variables","status":"completed","message":"Variables file created","percent":100}
{"timestamp":"2025-11-12T10:30:05Z","stage":"init","step":"store_credentials","status":"started","message":"Storing deployment credentials"}
{"timestamp":"2025-11-12T10:30:06Z","stage":"init","step":"store_credentials","status":"completed","message":"Credentials stored securely","percent":100}
{"timestamp":"2025-11-12T10:30:06Z","stage":"init","step":"generate_readme","status":"started","message":"Generating deployment README"}
{"timestamp":"2025-11-12T10:30:06Z","stage":"init","step":"generate_readme","status":"completed","message":"README generated","percent":100}
{"timestamp":"2025-11-12T10:30:06Z","stage":"init","step":"complete","status":"completed","message":"Deployment directory initialized successfully","percent":100}
```

### Successful Deploy (with percentage progress)

```json
{"timestamp":"2025-11-12T10:35:01Z","stage":"deploy","step":"begin","status":"started","message":"Starting Exasol deployment"}
{"timestamp":"2025-11-12T10:35:01Z","stage":"deploy","step":"tofu_init","status":"started","message":"Initializing OpenTofu"}
{"timestamp":"2025-11-12T10:35:15Z","stage":"deploy","step":"tofu_init","status":"completed","message":"OpenTofu initialized successfully","percent":100}
{"timestamp":"2025-11-12T10:35:15Z","stage":"deploy","step":"tofu_plan","status":"started","message":"Planning infrastructure changes"}
{"timestamp":"2025-11-12T10:35:25Z","stage":"deploy","step":"tofu_plan","status":"completed","message":"Infrastructure plan created","percent":100}
{"timestamp":"2025-11-12T10:35:25Z","stage":"deploy","step":"tofu_apply","status":"started","message":"Creating cloud infrastructure"}
{"timestamp":"2025-11-12T10:35:30Z","stage":"deploy","step":"tofu_apply","status":"in_progress","message":"Creating cloud infrastructure (Creating: aws_vpc.main)"}
{"timestamp":"2025-11-12T10:35:35Z","stage":"deploy","step":"tofu_apply","status":"in_progress","message":"Creating cloud infrastructure (1/8 resources)","percent":12}
{"timestamp":"2025-11-12T10:36:12Z","stage":"deploy","step":"tofu_apply","status":"in_progress","message":"Creating cloud infrastructure (Creating: aws_instance.exasol[0])"}
{"timestamp":"2025-11-12T10:36:45Z","stage":"deploy","step":"tofu_apply","status":"in_progress","message":"Creating cloud infrastructure (4/8 resources)","percent":50}
{"timestamp":"2025-11-12T10:38:30Z","stage":"deploy","step":"tofu_apply","status":"in_progress","message":"Creating cloud infrastructure (7/8 resources)","percent":87}
{"timestamp":"2025-11-12T10:38:45Z","stage":"deploy","step":"tofu_apply","status":"completed","message":"Cloud infrastructure created","percent":100}
{"timestamp":"2025-11-12T10:38:45Z","stage":"deploy","step":"wait_instances","status":"started","message":"Waiting for instances to initialize (60s)"}
{"timestamp":"2025-11-12T10:39:45Z","stage":"deploy","step":"wait_instances","status":"completed","message":"Instances ready","percent":100}
{"timestamp":"2025-11-12T10:39:45Z","stage":"deploy","step":"ansible_config","status":"started","message":"Configuring cluster with Ansible"}
{"timestamp":"2025-11-12T10:40:15Z","stage":"deploy","step":"ansible_config","status":"in_progress","message":"Configuring cluster (task: Install required packages (30s))","percent":25}
{"timestamp":"2025-11-12T10:41:30Z","stage":"deploy","step":"ansible_config","status":"in_progress","message":"Configuring cluster (task: Download Exasol database (75s))","percent":55}
{"timestamp":"2025-11-12T10:43:00Z","stage":"deploy","step":"ansible_config","status":"in_progress","message":"Configuring cluster (task: Initialize Exasol cluster (90s))","percent":75}
{"timestamp":"2025-11-12T10:44:45Z","stage":"deploy","step":"ansible_config","status":"in_progress","message":"Configuring cluster (task: Start database services (25s))","percent":88}
{"timestamp":"2025-11-12T10:45:20Z","stage":"deploy","step":"ansible_config","status":"in_progress","message":"Configuring cluster (finalizing)","percent":98}
{"timestamp":"2025-11-12T10:45:30Z","stage":"deploy","step":"ansible_config","status":"completed","message":"Cluster configured successfully","percent":100}
{"timestamp":"2025-11-12T10:45:30Z","stage":"deploy","step":"complete","status":"completed","message":"Deployment completed successfully","percent":100}
```

### Failed Deployment

```json
{"timestamp":"2025-11-12T10:35:01Z","stage":"deploy","step":"begin","status":"started","message":"Starting Exasol deployment"}
{"timestamp":"2025-11-12T10:35:01Z","stage":"deploy","step":"tofu_init","status":"started","message":"Initializing OpenTofu"}
{"timestamp":"2025-11-12T10:35:15Z","stage":"deploy","step":"tofu_init","status":"completed","message":"OpenTofu initialized successfully","percent":100}
{"timestamp":"2025-11-12T10:35:15Z","stage":"deploy","step":"tofu_plan","status":"started","message":"Planning infrastructure changes"}
{"timestamp":"2025-11-12T10:35:18Z","stage":"deploy","step":"tofu_plan","status":"failed","message":"Infrastructure planning failed"}
```

### Successful Destroy (with percentage progress)

```json
{"timestamp":"2025-11-12T11:00:01Z","stage":"destroy","step":"begin","status":"started","message":"Starting Exasol deployment destruction"}
{"timestamp":"2025-11-12T11:00:01Z","stage":"destroy","step":"confirm","status":"in_progress","message":"Waiting for user confirmation"}
{"timestamp":"2025-11-12T11:00:15Z","stage":"destroy","step":"confirm","status":"completed","message":"Destruction confirmed","percent":100}
{"timestamp":"2025-11-12T11:00:15Z","stage":"destroy","step":"tofu_destroy","status":"started","message":"Destroying cloud infrastructure"}
{"timestamp":"2025-11-12T11:00:25Z","stage":"destroy","step":"tofu_destroy","status":"in_progress","message":"Destroying cloud infrastructure (Destroying: aws_instance.exasol[2])"}
{"timestamp":"2025-11-12T11:01:10Z","stage":"destroy","step":"tofu_destroy","status":"in_progress","message":"Destroying cloud infrastructure (2/8 resources)","percent":25}
{"timestamp":"2025-11-12T11:02:30Z","stage":"destroy","step":"tofu_destroy","status":"in_progress","message":"Destroying cloud infrastructure (5/8 resources)","percent":62}
{"timestamp":"2025-11-12T11:03:35Z","stage":"destroy","step":"tofu_destroy","status":"in_progress","message":"Destroying cloud infrastructure (7/8 resources)","percent":87}
{"timestamp":"2025-11-12T11:03:45Z","stage":"destroy","step":"tofu_destroy","status":"completed","message":"Cloud infrastructure destroyed","percent":100}
{"timestamp":"2025-11-12T11:03:45Z","stage":"destroy","step":"cleanup","status":"started","message":"Cleaning up deployment files"}
{"timestamp":"2025-11-12T11:03:46Z","stage":"destroy","step":"cleanup","status":"completed","message":"Deployment files cleaned up","percent":100}
{"timestamp":"2025-11-12T11:03:46Z","stage":"destroy","step":"complete","status":"completed","message":"All resources destroyed successfully","percent":100}
```

## Percentage-Based Progress Tracking

For long-running operations like `tofu_apply`, `tofu_destroy`, and `ansible_config`, the progress tracking system parses the output in real-time to provide:

### OpenTofu/Terraform Progress
- Parses the plan output to determine total resources (e.g., "Plan: 8 to add")
- Tracks resource operations as they occur:
  - `Creating:`, `Modifying:`, `Destroying:` - Operation in progress
  - `Creation complete`, `Modification complete`, `Destruction complete` - Operation finished
- Emits progress updates showing:
  - Current resource being processed
  - Completed/total resources (e.g., "3/8 resources")
  - Percentage complete based on completed resources
- **Percentages never jump backwards** - Progress is monotonically increasing per stage:step

### Ansible Progress (Weighted by Task Type)
- Counts tasks as they are encountered (`TASK [task name]`)
- Tracks task completion (`ok:`, `changed:`, `failed:`, `skipping:`)
- **Weighted progress estimation** - Different task types have different weights:
  - **Heavy tasks (10x)**: Download, Install, Extract, Unpack
  - **Medium-heavy tasks (5x)**: Initialize, Setup, Configure, Build, Compile
  - **Medium tasks (3x)**: Copy, Update, Start, Restart
  - **Light tasks (1x)**: Other tasks (checks, validations, etc.)
- Shows current task name and duration in progress messages
- Calculates percentage based on completed weighted tasks vs. total estimated weight
- Caps at 95% until final completion to account for estimation errors
- **Percentages never jump backwards** - Progress is monotonically increasing per stage:step

**Example**: If a playbook has 1 download task (weight 10) and 9 check tasks (weight 1 each), completing the download shows ~50% progress, not ~10%, better reflecting actual time spent.

## Overall Progress Tracking

In addition to per-step percentages, each progress event includes an **`overall_percent`** field that shows progress across the entire stage (init, deploy, or destroy).

### How It Works

Each step in a stage has a **weight** representing its relative duration:

**Deploy Stage** (total: 100%):
- `begin`: 2% - Quick startup
- `tofu_init`: 5% - Initialize Terraform
- `tofu_plan`: 8% - Plan infrastructure
- `tofu_apply`: 30% - Create infrastructure (major step)
- `wait_instances`: 5% - Wait for instances
- `ansible_config`: 45% - Configure cluster (longest step)
- `complete`: 5% - Finalization

**Destroy Stage** (total: 100%):
- `begin`: 5%
- `confirm`: 5%
- `tofu_destroy`: 80% - Destroying resources (major step)
- `cleanup`: 5%
- `complete`: 5%

**Init Stage** (total: 100%):
- `validate_config`: 15%
- `create_directories`: 5%
- `initialize_state`: 10%
- `copy_templates`: 20%
- `generate_variables`: 15%
- `store_credentials`: 15%
- `generate_readme`: 10%
- `complete`: 10%

### Example Calculation

During deployment at `ansible_config` step showing 50%:
- Completed steps: `begin` (2%) + `tofu_init` (5%) + `tofu_plan` (8%) + `tofu_apply` (30%) + `wait_instances` (5%) = 50%
- Current step: `ansible_config` at 50% = 45% × 0.5 = 22.5%
- **Overall: 50% + 22.5% = 72.5%**

This means the deployment is ~73% complete overall, even though `ansible_config` is only halfway done.

## Progress File

All progress events are written to **`.exasol-progress.jsonl`** in the deployment directory:

- **Format**: JSON Lines (one JSON object per line)
- **Location**: `<deployment-directory>/.exasol-progress.jsonl`
- **Persistence**: File is preserved across operations
- **Immediate flush**: Each line is written immediately (no buffering)
- **Appending**: Each operation appends to the file (history is preserved)

This file can be:
- Monitored in real-time with `tail -f`
- Parsed by automation tools
- Used for debugging failed deployments
- Analyzed for operation timing and performance

### Example Usage

```bash
# Watch progress in real-time
tail -f my-deployment/.exasol-progress.jsonl | jq -r '.message'

# Get last progress event
tail -1 my-deployment/.exasol-progress.jsonl | jq .

# Count completed steps
grep '"status":"completed"' my-deployment/.exasol-progress.jsonl | wc -l

# Find all errors
jq 'select(.status == "failed")' my-deployment/.exasol-progress.jsonl
```

## Using Progress Output in UIs

### Bash/Shell Example

```bash
# Capture JSON to file and watch human-readable output
./exasol init --cloud-provider aws --deployment-dir ./my-deploy 2>&1 | tee >(grep '^{' > progress.json)

# Parse JSON in real-time with jq
./exasol deploy --deployment-dir ./my-deploy 2>/dev/null | jq -r '.message'
```

### Python Example

```python
import subprocess
import json
import sys

process = subprocess.Popen(
    ['./exasol', 'deploy', '--deployment-dir', './my-deploy'],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1
)

# Read progress events from stdout
for line in process.stdout:
    try:
        event = json.loads(line)
        print(f"[{event['stage']}:{event['step']}] {event['status']}: {event['message']}")

        # Update UI progress bar if percentage is available
        if 'percent' in event:
            update_progress_bar(event['percent'])
    except json.JSONDecodeError:
        pass

# Human-readable output is on stderr
for line in process.stderr:
    print(line, end='', file=sys.stderr)
```

### Node.js Example

```javascript
const { spawn } = require('child_process');

const deploy = spawn('./exasol', ['deploy', '--deployment-dir', './my-deploy']);

deploy.stdout.on('data', (data) => {
  const lines = data.toString().split('\n');
  lines.forEach(line => {
    if (line.trim()) {
      try {
        const event = JSON.parse(line);
        console.log(`[${event.stage}:${event.step}] ${event.status}: ${event.message}`);

        // Handle different statuses
        if (event.status === 'failed') {
          handleError(event);
        } else if (event.status === 'completed' && event.step === 'complete') {
          handleSuccess(event);
        }
      } catch (e) {
        // Not JSON, ignore
      }
    }
  });
});

deploy.stderr.on('data', (data) => {
  // Human-readable output
  console.error(data.toString());
});
```

## Implementation Details

The progress tracking system is implemented in [lib/common.sh](lib/common.sh):

- `progress_emit()` - Core function that emits JSON to stdout and human-readable to stderr
- `progress_start()` - Mark a step as started
- `progress_update()` - Mark a step as in progress (with optional percentage)
- `progress_complete()` - Mark a step as completed
- `progress_fail()` - Mark a step as failed

## Best Practices

1. **Parse stdout for JSON**: The JSON progress events are always on stdout
2. **Display stderr for humans**: Human-readable output with colors and emojis is on stderr
3. **Use the progress file**: Read from `.exasol-progress.jsonl` for persistent progress tracking
4. **Handle incomplete lines**: Buffer stdout until you receive a complete JSON object
5. **Check status field**: Use `status` to determine if a step succeeded or failed
6. **Track stage+step**: The combination of `stage` and `step` uniquely identifies the current operation
7. **Use percent when available**: Not all steps report percentage, but when they do, use it for progress bars
8. **Percentages are monotonic**: Progress percentages never decrease within a stage:step
9. **Handle failures gracefully**: When `status: "failed"` is received, the process will exit soon after
10. **Monitor the progress file**: Use `tail -f` on `.exasol-progress.jsonl` for real-time updates from another process

## Notes

- Progress events are emitted in real-time as operations progress
- Each step typically has at least a `started` and either `completed` or `failed` status
- Long-running operations may emit multiple `in_progress` events with updated percentages
- The process exit code indicates overall success (0) or failure (non-zero)
- Log level (`--log-level`) only affects stderr output, not JSON progress events
