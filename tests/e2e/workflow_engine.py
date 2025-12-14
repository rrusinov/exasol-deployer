#!/usr/bin/env python3
"""
Workflow-Based E2E Test Engine

Extends the existing e2e framework to support workflow-based testing with:
- Sequential step execution (init, deploy, stop, start, restart, crash)
- Per-step validation with custom checks
- Node-specific operations
- External command execution for verification
- Retry logic and failure handling

Validation Check Syntax
=======================

Dynamic validation checks use data from `exasol status` and `exasol health` commands.

1. Cluster Status Checks (from `exasol status` -> .exasol.json)
   ---------------------------------------------------------------
   Format: cluster_status==<value> or cluster_status!=<value>
   
   Examples:
   - cluster_status==database_ready  # Cluster is ready
   - cluster_status==stopped         # Cluster is stopped
   - cluster_status!=error           # Cluster is not in error state
   
   Common status values: database_ready, stopped, starting, error, degraded

2. Health Status Checks (from `exasol health`)
   --------------------------------------------
   Format: health_status[<nodes>].<component>==<value>
          health_status[<nodes>].<component>!=<value>
   
   Node Selectors:
   - [*]           - All nodes
   - [n11]         - Specific node n11
   - [n11,n12,n13] - Multiple nodes
   
   Component Selectors (mapped to JSON fields from `exasol health`):
   - .ssh          - SSH connectivity to host
   - .adminui      - Admin UI port 8443 accessibility
   - .database     - Database port 8563 accessibility
   - .cos_ssh      - COS SSH connectivity
   
   Value Comparisons:
   - "ok" maps to true
   - "failed" maps to false
   - Can also use "true"/"false" directly
   
   Examples:
   - health_status[*].ssh==ok              # SSH OK on all nodes
   - health_status[*].adminui==ok          # Admin UI accessible on all nodes
   - health_status[n11].ssh!=ok            # SSH not OK on n11 (node down)
   - health_status[n12,n13].database==ok   # DB port OK on n12 and n13
   - health_status[*].database!=failed     # No database failures on any node
"""

import json
import logging
import os
import shlex
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Any, Optional, Callable
from dataclasses import dataclass, field
from enum import Enum


class StepStatus(Enum):
    """Status of a workflow step execution"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass
class ValidationCheck:
    """Represents a single validation check"""
    name: str
    description: str
    check_function: Callable[[Dict[str, Any]], bool]
    allow_failure: bool = False
    retry_config: Optional[Dict[str, int]] = None


@dataclass
class WorkflowStep:
    """Represents a single step in a workflow"""
    step_type: str
    description: str
    status: StepStatus = StepStatus.PENDING
    duration: float = 0.0
    error: Optional[str] = None
    result: Optional[Dict[str, Any]] = None
    validation_results: List[Dict[str, Any]] = field(default_factory=list)

    # Step-specific parameters
    target_node: Optional[str] = None
    method: Optional[str] = None
    command: Optional[str] = None
    script: Optional[str] = None
    checks: List[str] = field(default_factory=list)
    allow_failures: List[str] = field(default_factory=list)
    retry: Optional[Dict[str, int]] = None


class ValidationRegistry:
    """Registry of validation check functions"""

    def __init__(self, deploy_dir: Path, provider: str, logger: logging.Logger, exasol_bin: Optional[Path] = None):
        self.deploy_dir = deploy_dir
        self.provider = provider
        self.logger = logger
        self.exasol_bin = exasol_bin or Path('./exasol')  # Use installed binary or fallback to source
        self.checks: Dict[str, ValidationCheck] = {}
        self._register_default_checks()

    def _register_default_checks(self):
        """Register default validation checks
        
        Dynamic checks support:
        - cluster_status==<value> or cluster_status!=<value>
          Example: cluster_status==database_ready, cluster_status!=stopped
          
        - health_status[<nodes>].<component>==<value> or !=<value>
          Examples:
            health_status[*].ssh==ok              - SSH OK on all nodes (checks ssh_ok field)
            health_status[*].adminui==ok          - Admin UI on all nodes (checks port_8443_ok field)
            health_status[*].database==ok         - DB port on all nodes (checks port_8563_ok field)
            health_status[n11].ssh!=ok            - SSH not OK on n11
            health_status[n12,n13].adminui==ok    - Admin UI OK on n12 and n13
        """
        pass  # No static checks registered

    def register(self, name: str, description: str, check_func: Callable,
                 allow_failure: bool = False, retry_config: Optional[Dict] = None):
        """Register a validation check"""
        self.checks[name] = ValidationCheck(
            name=name,
            description=description,
            check_function=check_func,
            allow_failure=allow_failure,
            retry_config=retry_config
        )

    def get_check(self, check_name: str) -> Optional[ValidationCheck]:
        """Get a validation check by name, supporting dynamic checks
        
        Supported dynamic check formats:
        - cluster_status==<value> or cluster_status!=<value>
        - health_status[<nodes>].<component>==<value> or !=<value>
        """
        # Handle cluster_status checks with comparison
        if check_name.startswith("cluster_status"):
            if "==" in check_name or "!=" in check_name:
                return self._create_cluster_status_check(check_name)
        
        # Handle health_status checks with node/component selection
        if check_name.startswith("health_status["):
            return self._create_health_status_check(check_name)
        
        # Fall back to registered static checks
        return self.checks.get(check_name)

    def _run_exasol_command(self, command: str, *args, timeout: int = 360) -> subprocess.CompletedProcess:
        """Run exasol CLI command"""
        cmd = [str(self.exasol_bin), command, '--deployment-dir', str(self.deploy_dir)]
        cmd.extend(args)
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

    def _read_state(self) -> Dict[str, Any]:
        """Read deployment state from .exasol.json"""
        state_file = self.deploy_dir / '.exasol.json'
        if state_file.exists():
            with open(state_file, 'r') as f:
                return json.load(f)
        return {}

    def _run_exasol_health(self, verbosity: str = 'quiet', timeout: int = 360) -> Dict[str, Any]:
        """Run exasol health command and return parsed JSON"""
        try:
            cmd_args = ['health']
            if verbosity == 'verbose':
                cmd_args.append('--verbose')
            elif verbosity == 'quiet':
                cmd_args.append('--quiet')
            cmd_args.extend(['--output-format', 'json'])
            result = self._run_exasol_command(*cmd_args, timeout=timeout)
        except subprocess.TimeoutExpired as e:
            self.logger.error(f"Health check command timed out after {timeout} seconds")
            # Return structure indicating health check unavailable due to timeout
            return {
                'status': 'timeout',
                'checks': {
                    'ssh': {'passed': 0, 'failed': 0},
                    'services': {'active': 0, 'failed': 0},
                    'adminui': {'passed': 0, 'failed': 0},
                    'database': {'passed': 0, 'failed': 0},
                    'cos_ssh': {'passed': 0, 'failed': 0}
                },
                'issues_count': 0,
                'issues': [f"Health check timed out after {timeout} seconds"]
            }
        
        # Try to parse JSON output first, even if command failed
        # Health command returns exit code 1 when issues are detected,
        # but still outputs valid JSON with actual check results
        try:
            health_data = json.loads(result.stdout)
            return health_data
        except json.JSONDecodeError as e:
            # If JSON parsing failed, check if it's because deployment doesn't exist
            if result.returncode != 0:
                # Only log error once with debug level to avoid spam
                # The actual validation check will fail with a proper error message
                self.logger.debug(f"Health check command failed: {result.stderr.strip()}")
                # Return a structure indicating all health checks unavailable
                # This handles the case where deployment doesn't exist yet (after init)
                # or has been destroyed (after destroy)
                return {
                    'status': 'unavailable',
                    'checks': {
                        'ssh': {'passed': 0, 'failed': 0},
                        'services': {'active': 0, 'failed': 0},
                        'adminui': {'passed': 0, 'failed': 0},
                        'database': {'passed': 0, 'failed': 0},
                        'cos_ssh': {'passed': 0, 'failed': 0}
                    },
                    'issues_count': 0,
                    'issues': []
                }
            else:
                self.logger.error(f"Failed to parse health JSON: {e}")
                return {}

    def _create_cluster_status_check(self, check_name: str) -> ValidationCheck:
        """Create a dynamic cluster status check
        
        Format: cluster_status==<value> or cluster_status!=<value>
        Examples: cluster_status==database_ready, cluster_status!=stopped
        """
        import re
        
        # Parse the check expression
        if "==" in check_name:
            operator = "=="
            _, expected = check_name.split("==", 1)
        elif "!=" in check_name:
            operator = "!="
            _, expected = check_name.split("!=", 1)
        else:
            # Legacy support for plain "cluster_status" (assume ==database_ready)
            operator = "=="
            expected = "database_ready"
        
        expected = expected.strip()
        
        def check_func(context: Dict[str, Any]) -> bool:
            state = self._read_state()
            actual = state.get('status', '')
            
            if operator == "==":
                return actual == expected
            else:  # !=
                return actual != expected
        
        description = f"Cluster status {operator} {expected}"
        return ValidationCheck(
            name=check_name,
            description=description,
            check_function=check_func
        )

    def _create_health_status_check(self, check_name: str) -> ValidationCheck:
        """Create a dynamic health status check
        
        Format: health_status[<nodes>].<component>==<value> or !=<value>
        
        Node selectors:
        - [*] - all nodes
        - [n11] - specific node
        - [n11,n12,n13] - multiple nodes
        
        Component selectors (mapped to exasol health JSON checks):
        - .ssh -> checks 'ssh' component
        - .adminui -> checks 'adminui' component
        - .database -> checks 'database' component
        - .cos_ssh -> checks 'cos_ssh' component
        
        Expected values:
        - For ssh/adminui/database/cos_ssh: "ok" maps to true, "failed" maps to false
        - Or use "true"/"false" directly
        
        Examples:
        - health_status[*].ssh==ok -> all nodes have ssh_ok=true
        - health_status[*].adminui==ok -> all nodes have port_8443_ok=true
        - health_status[n11].ssh!=ok -> n11 has ssh_ok=false
        - health_status[n12,n13].database==ok -> n12 and n13 have port_8563_ok=true
        """
        import re
        
        # Parse: health_status[nodes].component==value or !=value
        match = re.match(r'health_status\[([^\]]+)\]\.([^=!]+)(==|!=)(.+)', check_name)
        if not match:
            raise ValueError(f"Invalid health_status check format: {check_name}")
        
        node_selector = match.group(1).strip()
        component = match.group(2).strip()
        operator = match.group(3)
        expected_value = match.group(4).strip()
        
        # Component names are used directly in the checks structure
        valid_components = {'ssh', 'adminui', 'database', 'cos_ssh'}
        
        # Map expected values: "ok" -> "true", "failed" -> "false"
        value_map = {
            'ok': 'true',
            'failed': 'false'
        }
        mapped_expected = value_map.get(expected_value.lower(), expected_value)
        
        # Validate component
        if component not in valid_components:
            raise ValueError(f"Unknown health check component: {component}. Valid: {', '.join(sorted(valid_components))}")
        
        # Parse node selector
        if node_selector == '*':
            nodes = None  # Will match all nodes
        else:
            nodes = [n.strip() for n in node_selector.split(',')]
        
        def check_func(context: Dict[str, Any]) -> bool:
            health_data = self._run_exasol_health(timeout=60)
            if not health_data:
                self.logger.error("Health command returned no data")
                return False
            
            # Actual exasol health --output-format json structure:
            # {
            #   "status": "healthy" | "issues_detected",
            #   "checks": {
            #     "ssh": {"passed": N, "failed": M},
            #     "services": {"active": N, "failed": M},
            #     "adminui": {"passed": N, "failed": M},
            #     "database": {"passed": N, "failed": M},
            #     "cos_ssh": {"passed": N, "failed": M}
            #   },
            #   "issues_count": N,
            #   "issues": [...]
            # }
            
            # Map component to the checks structure
            component_to_check_map = {
                'ssh': 'ssh',
                'adminui': 'adminui',
                'database': 'database',
                'cos_ssh': 'cos_ssh',
            }
            
            check_key = component_to_check_map.get(component, component)
            
            if 'checks' not in health_data or check_key not in health_data['checks']:
                self.logger.error(f"Health data missing checks.{check_key}")
                return False
            
            check_data = health_data['checks'][check_key]
            
            # For wildcard (*), check all nodes passed
            # For specific nodes, we can't check per-node in current health format
            # So we check that overall health is good
            if node_selector == '*':
                # All nodes should pass
                passed = check_data.get('passed', 0)
                failed = check_data.get('failed', 0)
                
                if operator == "==":
                    if mapped_expected.lower() == 'true':  # Expecting OK
                        result = failed == 0 and passed > 0
                        if not result:
                            self.logger.debug(f"Check failed: {check_key} has {failed} failures, {passed} passed")
                        return result
                    else:  # Expecting failed
                        result = failed > 0
                        if not result:
                            self.logger.debug(f"Check failed: expected failures but got {failed} failures")
                        return result
                else:  # !=
                    if mapped_expected.lower() == 'true':  # Expecting NOT OK
                        result = failed > 0 or passed == 0
                        if not result:
                            self.logger.debug(f"Check failed: expected failures but got {failed} failures, {passed} passed")
                        return result
                    else:  # Expecting NOT failed
                        result = failed == 0 and passed > 0
                        if not result:
                            self.logger.debug(f"Check failed: {check_key} has {failed} failures")
                        return result
            else:
                # Specific nodes requested, but we can't check per-node with current health format
                # Fall back to checking overall health
                self.logger.warning(f"Per-node health checks not supported yet, checking overall {check_key} health")
                passed = check_data.get('passed', 0)
                failed = check_data.get('failed', 0)
                
                if operator == "==":
                    if mapped_expected.lower() == 'true':
                        return failed == 0 and passed > 0
                    else:
                        return failed > 0
                else:  # !=
                    if mapped_expected.lower() == 'true':
                        return failed > 0 or passed == 0
                    else:
                        return failed == 0 and passed > 0
        
        description = f"Health check: {node_selector}.{component} {operator} {expected_value}"
        return ValidationCheck(
            name=check_name,
            description=description,
            check_function=check_func
        )




class WorkflowExecutor:
    """Executes workflow-based test scenarios"""

    def __init__(self, deploy_dir: Path, provider: str, logger: logging.Logger,
                 log_callback: Optional[Callable] = None, db_version: Optional[str] = None,
                 exasol_bin: Optional[Path] = None, debug_mode: bool = False):
        self.deploy_dir = deploy_dir
        self.provider = provider
        self.logger = logger
        self.log_callback = log_callback or (lambda msg: logger.info(msg))
        self.exasol_bin = exasol_bin or Path('./exasol')  # Use installed binary or fallback to source
        self.validation_registry = ValidationRegistry(deploy_dir, provider, logger, self.exasol_bin)
        self.context: Dict[str, Any] = {}
        self.db_version = db_version  # Optional database version override
        self.debug_mode = debug_mode  # Enable verbose Ansible output and additional debugging

    def _run_command_with_streaming(self, cmd: List[str], timeout: int) -> subprocess.CompletedProcess:
        """Run a command and stream output in real-time to log_callback.
        
        Returns a CompletedProcess-like object with stdout, stderr, and returncode.
        """
        cmd_str = ' '.join(cmd)
        self.log_callback(f"Running command: {cmd_str}")
        
        # Use Popen to stream output in real-time
        # Ensure proper locale environment for ansible-playbook validation
        env = os.environ.copy()
        env.update({
            'LC_ALL': 'en_US.UTF-8',
            'LANG': 'en_US.UTF-8'
        })
        
        # Add debug environment variables when debug mode is enabled
        if self.debug_mode:
            env.update({
                'ANSIBLE_VERBOSITY': '3',  # Ansible verbose level (0-4)
                'ANSIBLE_DEBUG': '1',      # Enable Ansible debug output
                'ANSIBLE_STDOUT_CALLBACK': 'debug',  # Use debug callback for detailed output
                'ANSIBLE_DISPLAY_SKIPPED_HOSTS': 'True',  # Show skipped hosts
                'ANSIBLE_DISPLAY_OK_HOSTS': 'True',       # Show successful hosts
            })
            self.log_callback("Debug mode enabled - Ansible will run with verbose output")
        
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,  # Line buffered
            env=env
        )
        
        stdout_lines = []
        stderr_lines = []
        
        import select
        import sys
        
        # Stream both stdout and stderr in real-time
        streams = {
            process.stdout.fileno(): ('stdout', stdout_lines),
            process.stderr.fileno(): ('stderr', stderr_lines)
        }
        
        start_time = time.time()
        while True:
            # Check timeout
            if timeout and time.time() - start_time > timeout:
                process.kill()
                process.wait()
                raise subprocess.TimeoutExpired(cmd, timeout)
            
            # Check if process finished
            if process.poll() is not None:
                # Read any remaining output
                for line in process.stdout:
                    self.log_callback(line.rstrip())
                    stdout_lines.append(line)
                for line in process.stderr:
                    self.log_callback(line.rstrip())
                    stderr_lines.append(line)
                break
            
            # Use select to check which streams have data (Unix only)
            if hasattr(select, 'select'):
                ready, _, _ = select.select(list(streams.keys()), [], [], 0.1)
                for fd in ready:
                    stream_name, line_list = streams[fd]
                    line = process.stdout.readline() if stream_name == 'stdout' else process.stderr.readline()
                    if line:
                        self.log_callback(line.rstrip())
                        line_list.append(line)
            else:
                # Fallback for non-Unix (Windows) - read line by line with small delay
                time.sleep(0.1)
                if process.stdout:
                    line = process.stdout.readline()
                    if line:
                        self.log_callback(line.rstrip())
                        stdout_lines.append(line)
                if process.stderr:
                    line = process.stderr.readline()
                    if line:
                        self.log_callback(line.rstrip())
                        stderr_lines.append(line)
        
        returncode = process.wait()
        self.log_callback(f"Command exited with {returncode}")
        
        # Create a result object similar to subprocess.CompletedProcess
        class Result:
            def __init__(self, args, returncode, stdout, stderr):
                self.args = args
                self.returncode = returncode
                self.stdout = stdout
                self.stderr = stderr
        
        return Result(cmd, returncode, ''.join(stdout_lines), ''.join(stderr_lines))

    def execute_workflow(self, workflow: List[Dict[str, Any]],
                        params: Dict[str, Any]) -> List[WorkflowStep]:
        """Execute a complete workflow"""
        results = []
        self.context = {'parameters': params, 'deploy_dir': str(self.deploy_dir)}

        for step_config in workflow:
            step = self._parse_step_config(step_config)
            self.log_callback(f"STEP: {step.description}")

            step_result = self._execute_step(step, params)
            results.append(step_result)

            # Stop workflow if step failed
            if step_result.status == StepStatus.FAILED:
                self.logger.error(f"Step failed: {step.description} - {step.error}")
                break

        return results

    def _parse_step_config(self, config: Dict[str, Any]) -> WorkflowStep:
        """Parse step configuration into WorkflowStep object"""
        step_type = config['step']
        # Use step type as description if none provided
        description = config.get('description', step_type)
        return WorkflowStep(
            step_type=step_type,
            description=description,
            target_node=config.get('target_node'),
            method=config.get('method'),
            command=config.get('command'),
            script=config.get('script'),
            checks=config.get('checks', []),
            allow_failures=config.get('allow_failures', []),
            retry=config.get('retry')
        )

    def _execute_step(self, step: WorkflowStep, params: Dict[str, Any]) -> WorkflowStep:
        """Execute a single workflow step"""
        start_time = time.time()
        step.status = StepStatus.RUNNING

        try:
            # Execute step based on type
            if step.step_type == 'init':
                self._execute_init(step, params)
            elif step.step_type == 'deploy':
                self._execute_deploy(step)
            elif step.step_type == 'validate':
                self._execute_validate(step)
            elif step.step_type == 'stop_cluster':
                self._execute_stop_cluster(step)
            elif step.step_type == 'start_cluster':
                self._execute_start_cluster(step)
            elif step.step_type == 'restart_node':
                self._execute_restart_node(step)
            elif step.step_type == 'custom_command':
                self._execute_custom_command(step)
            elif step.step_type == 'destroy':
                self._execute_destroy(step)
            else:
                raise ValueError(f"Unknown step type: {step.step_type}")

            step.status = StepStatus.COMPLETED

        except Exception as e:
            step.status = StepStatus.FAILED
            step.error = str(e)
            self.logger.error(f"Step failed: {step.description} - {e}")

        finally:
            step.duration = time.time() - start_time

        return step

    def _execute_init(self, step: WorkflowStep, params: Dict[str, Any]):
        """Execute init step.
        
        All SUT parameters are dynamically mapped from config_schema.SUT_PARAMETERS.
        Parameter names use underscores and map 1:1 to CLI flags (underscore -> hyphen).
        
        See tests/e2e/config_schema.py SUT_PARAMETERS for the complete list of supported parameters.
        """
        cmd = [
            str(self.exasol_bin), 'init',
            '--cloud-provider', self.provider,
            '--deployment-dir', str(self.deploy_dir)
        ]

        # Add database version if provided
        if self.db_version:
            cmd.extend(['--db-version', self.db_version])

        # Import parameter schema
        try:
            from config_schema import SUT_PARAMETERS
        except ImportError:
            # Fallback to basic parameter map if schema not available
            SUT_PARAMETERS = {}

        # Build parameter map from schema
        param_map = {}
        boolean_flags = {}
        
        for param_name, param_def in SUT_PARAMETERS.items():
            cli_flag = param_def.get('cli_flag')
            param_type = param_def.get('type')
            
            if cli_flag:
                if param_type == 'bool':
                    boolean_flags[param_name] = cli_flag
                else:
                    param_map[param_name] = cli_flag

        # Add parameters with values
        for key, flag in param_map.items():
            if key in params:
                cmd.extend([flag, str(params[key])])
        
        # Add boolean flags (parameters that don't take values)
        for key, flag in boolean_flags.items():
            if params.get(key):
                cmd.append(flag)

        # Run command with real-time output streaming
        result = self._run_command_with_streaming(cmd, timeout=300)
        
        if result.returncode != 0:
            raise RuntimeError(f"Init failed: {result.stderr}")

        step.result = {'stdout': result.stdout, 'stderr': result.stderr}

    def _execute_deploy(self, step: WorkflowStep):
        """Execute deploy step"""
        cmd = [str(self.exasol_bin), 'deploy', '--deployment-dir', str(self.deploy_dir)]
        
        result = self._run_command_with_streaming(cmd, timeout=3600)
        
        if result.returncode != 0:
            raise RuntimeError(f"Deploy failed: {result.stderr}")

        step.result = {'stdout': result.stdout, 'stderr': result.stderr}

    def _execute_validate(self, step: WorkflowStep):
        """Execute validation step with multiple checks"""
        validation_results = []

        for check_name in step.checks:
            check = self.validation_registry.get_check(check_name)
            if not check:
                self.logger.warning(f"Unknown check: {check_name}")
                continue

            # Execute check with retry if configured
            retry_config = step.retry or check.retry_config
            max_attempts = retry_config.get('max_attempts', 1) if retry_config else 1
            delay = retry_config.get('delay_seconds', 5) if retry_config else 5

            check_passed = False
            attempt = 0
            last_error = None

            while attempt < max_attempts and not check_passed:
                attempt += 1
                try:
                    check_passed = check.check_function(self.context)
                    if not check_passed and attempt < max_attempts:
                        self.logger.info(f"Check {check_name} failed, retrying in {delay}s ({attempt}/{max_attempts})")
                        time.sleep(delay)
                except Exception as e:
                    last_error = str(e)
                    if attempt < max_attempts:
                        time.sleep(delay)

            allow_failure = check_name in step.allow_failures or check.allow_failure

            validation_results.append({
                'check': check_name,
                'passed': check_passed,
                'attempts': attempt,
                'allow_failure': allow_failure,
                'error': last_error
            })

            if not check_passed and not allow_failure:
                # Run verbose health check for debugging if this is a health_status check
                if check_name.startswith('health_status'):
                    self.logger.info("Running health checks for debugging...")
                    try:
                        import subprocess
                        # Get JSON output for structured logging
                        cmd = [str(self.exasol_bin), 'health', '--deployment-dir', str(self.deploy_dir), '--output-format', 'json', '--quiet']
                        json_result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                        self.logger.info("Health check JSON: " + json_result.stdout.strip())

                        # Get verbose text output for detailed debugging
                        cmd = [str(self.exasol_bin), 'health', '--deployment-dir', str(self.deploy_dir), '--verbose', '--quiet']
                        verbose_result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                        self.logger.info("Verbose health check output:\n" + verbose_result.stdout)
                    except Exception as e:
                        self.logger.error(f"Failed to run health checks for debugging: {e}")

                step.validation_results = validation_results
                raise RuntimeError(f"Validation check failed: {check_name}")

        step.validation_results = validation_results
        step.result = {'all_passed': all(r['passed'] or r['allow_failure'] for r in validation_results)}

    def _execute_stop_cluster(self, step: WorkflowStep):
        """Execute cluster stop"""
        cmd = [str(self.exasol_bin), 'stop', '--deployment-dir', str(self.deploy_dir)]
        
        result = self._run_command_with_streaming(cmd, timeout=600)
        
        if result.returncode != 0:
            raise RuntimeError(f"Stop cluster failed: {result.stderr}")

        step.result = {'stdout': result.stdout, 'stderr': result.stderr}

    def _execute_start_cluster(self, step: WorkflowStep):
        """Execute cluster start"""
        cmd = [str(self.exasol_bin), 'start', '--deployment-dir', str(self.deploy_dir)]
        # Allow up to 20 minutes for start to handle slower provider boots (e.g., GCP)
        result = self._run_command_with_streaming(cmd, timeout=1200)
        
        if result.returncode != 0:
            raise RuntimeError(f"Start cluster failed: {result.stderr}")

        step.result = {'stdout': result.stdout, 'stderr': result.stderr}

    def _execute_destroy(self, step: WorkflowStep):
        """Execute destroy step to tear down the cluster"""
        cmd = [str(self.exasol_bin), 'destroy', '--deployment-dir', str(self.deploy_dir), '--auto-approve']
        
        result = self._run_command_with_streaming(cmd, timeout=600)
        
        if result.returncode != 0:
            raise RuntimeError(f"Destroy failed: {result.stderr}")

        step.result = {'stdout': result.stdout, 'stderr': result.stderr}

    def _execute_restart_node(self, step: WorkflowStep):
        """Restart a specific node via SSH reboot command"""
        if not step.target_node:
            raise ValueError("target_node is required for restart_node")

        method = step.method or "ssh"

        if method != "ssh":
            raise ValueError(f"Only method='ssh' is supported for restart_node, got: {method}")

        if method == "ssh":
            # Reboot via SSH command - supported for all providers
            # Read inventory to get the node's SSH hostname
            inventory_path = self.deploy_dir / "inventory.ini"
            ssh_config_path = self.deploy_dir / "ssh_config"

            if not inventory_path.exists():
                raise RuntimeError(f"Inventory file not found: {inventory_path}")

            # Find the target node in inventory
            node_host = None
            with open(inventory_path, 'r') as f:
                in_nodes_section = False
                for line in f:
                    line = line.strip()
                    if line == "[exasol_nodes]":
                        in_nodes_section = True
                        continue
                    if line.startswith("["):
                        in_nodes_section = False
                    if in_nodes_section and line and not line.startswith("#"):
                        # Parse line like "n11 ansible_host=..."
                        parts = line.split()
                        if parts and parts[0] == step.target_node:
                            node_host = parts[0]
                            break

            if not node_host:
                raise RuntimeError(f"Could not find node {step.target_node} in inventory")

            # Execute reboot via SSH
            ssh_cmd = ['ssh', '-F', str(ssh_config_path), '-o', 'BatchMode=yes',
                      '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=10',
                      node_host, 'sudo', 'reboot']

            result = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=30)

            # SSH connection may drop during reboot, so non-zero exit is expected
            step.result = {'method': 'ssh', 'node': step.target_node,
                          'command': ' '.join(ssh_cmd)}

    def _execute_custom_command(self, step: WorkflowStep):
        """Execute a custom shell command with variable substitution
        
        Supported variables:
        - $deployment_dir: Path to the deployment directory (absolute path)
        - $provider: Cloud provider name
        
        Supports retry logic via step.retry configuration:
        - max_attempts: Number of retry attempts (default: 1)
        - delay_seconds: Delay between retries (default: 10)
        """
        if not step.command and not step.script:
            raise ValueError("command or script is required for custom_command step")
        
        script_dir = Path(__file__).resolve().parent / 'custom_commands'
        command = None
        if step.script:
            script_spec = step.script
            script_spec = script_spec.replace('$deployment_dir', str(self.deploy_dir.resolve()))
            script_spec = script_spec.replace('$provider', self.provider)
            script_parts = shlex.split(script_spec)
            if not script_parts:
                raise ValueError("script is required for custom_command step")
            script_path = Path(script_parts[0])
            if not script_path.is_absolute():
                script_path = script_dir / script_parts[0]
            if not script_path.exists():
                raise RuntimeError(f"Custom command script not found: {script_path}")
            if not os.access(script_path, os.X_OK):
                raise RuntimeError(f"Custom command script is not executable: {script_path}")
            script_parts[0] = str(script_path)
            command = ' '.join(shlex.quote(part) for part in script_parts)
        else:
            command = step.command
            command = command.replace('$deployment_dir', str(self.deploy_dir.resolve()))
            command = command.replace('$provider', self.provider)
        
        # Get retry configuration
        max_attempts = 1
        delay_seconds = 10
        if step.retry:
            max_attempts = step.retry.get('max_attempts', 1)
            delay_seconds = step.retry.get('delay_seconds', 10)
        
        self.log_callback(f"Executing custom command: {command}")
        
        last_error = None
        for attempt in range(1, max_attempts + 1):
            # Execute command using shell to support piping and redirection
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=300,
                cwd=self.deploy_dir.parent  # Execute from parent of deployment dir
            )
            
            # Log output
            if result.stdout:
                self.log_callback(f"STDOUT: {result.stdout}")
            if result.stderr:
                self.log_callback(f"STDERR: {result.stderr}")
            
            if result.returncode == 0:
                # Success
                step.result = {
                    'command': command,
                    'stdout': result.stdout,
                    'stderr': result.stderr,
                    'returncode': result.returncode,
                    'attempts': attempt
                }
                return
            
            # Command failed
            last_error = f"Custom command failed with exit code {result.returncode}: {result.stderr}"
            
            if attempt < max_attempts:
                self.log_callback(f"Attempt {attempt}/{max_attempts} failed, retrying in {delay_seconds}s...")
                time.sleep(delay_seconds)
            else:
                self.log_callback(f"All {max_attempts} attempts failed")
        
        # All attempts failed
        raise RuntimeError(last_error)
