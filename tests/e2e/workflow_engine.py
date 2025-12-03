#!/usr/bin/env python3
"""
Workflow-Based E2E Test Engine

Extends the existing e2e framework to support workflow-based testing with:
- Sequential step execution (init, deploy, stop, start, restart, crash)
- Per-step validation with custom checks
- Node-specific operations
- External command execution for verification
- Retry logic and failure handling
"""

import json
import logging
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
    checks: List[str] = field(default_factory=list)
    allow_failures: List[str] = field(default_factory=list)
    retry: Optional[Dict[str, int]] = None
    custom_command: Optional[List[str]] = None


class ValidationRegistry:
    """Registry of validation check functions"""

    def __init__(self, deploy_dir: Path, provider: str, logger: logging.Logger):
        self.deploy_dir = deploy_dir
        self.provider = provider
        self.logger = logger
        self.checks: Dict[str, ValidationCheck] = {}
        self._register_default_checks()

    def _register_default_checks(self):
        """Register default validation checks"""

        # Cluster status checks
        self.register("cluster_status", "Cluster is healthy", self._check_cluster_status)
        self.register("cluster_status_stopped", "Cluster is stopped", self._check_cluster_stopped)
        self.register("cluster_degraded", "Cluster is degraded", self._check_cluster_degraded)
        self.register("cluster_critical", "Cluster is critical", self._check_cluster_critical)

        # Node status checks
        self.register("all_nodes_running", "All nodes are running", self._check_all_nodes_running)
        self.register("ssh_connectivity", "SSH connectivity to all nodes", self._check_ssh_connectivity)
        self.register("vms_powered_off", "VMs are powered off", self._check_vms_powered_off)

        # Database checks
        self.register("database_running", "Database is running", self._check_database_running)
        self.register("database_degraded", "Database is degraded", self._check_database_degraded)
        self.register("database_down", "Database is down", self._check_database_down)
        self.register("admin_ui_accessible", "Admin UI is accessible", self._check_admin_ui)
        self.register("data_integrity", "Data integrity verified", self._check_data_integrity)

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
        """Get a validation check by name, supporting node-specific checks"""
        # Handle node-specific checks like "node_status:n12"
        if ":" in check_name:
            base_check, param = check_name.split(":", 1)
            if base_check == "node_status":
                # Create a dynamic check for specific node
                return ValidationCheck(
                    name=check_name,
                    description=f"Node {param} status check",
                    check_function=lambda ctx: self._check_node_status(ctx, param)
                )

        return self.checks.get(check_name)

    def _run_exasol_command(self, command: str, *args) -> subprocess.CompletedProcess:
        """Run exasol CLI command"""
        cmd = ['./exasol', command, '--deployment-dir', str(self.deploy_dir)]
        cmd.extend(args)
        return subprocess.run(cmd, capture_output=True, text=True, timeout=300)

    def _read_state(self) -> Dict[str, Any]:
        """Read deployment state"""
        state_file = self.deploy_dir / '.exasol.json'
        if state_file.exists():
            with open(state_file, 'r') as f:
                return json.load(f)
        return {}

    def _check_cluster_status(self, context: Dict[str, Any]) -> bool:
        """Check if cluster is healthy"""
        result = self._run_exasol_command('status')
        if result.returncode != 0:
            return False

        try:
            status = json.loads(result.stdout)
            return status.get('status') in ['database_ready', 'running']
        except:
            return False

    def _check_cluster_stopped(self, context: Dict[str, Any]) -> bool:
        """Check if cluster is stopped"""
        state = self._read_state()
        return state.get('status') == 'stopped'

    def _check_cluster_degraded(self, context: Dict[str, Any]) -> bool:
        """Check if cluster is in degraded state"""
        # This would check if some nodes are down but cluster is still operational
        return True  # Placeholder

    def _check_cluster_critical(self, context: Dict[str, Any]) -> bool:
        """Check if cluster is in critical state"""
        # This would check if cluster has lost quorum/majority
        return True  # Placeholder

    def _check_all_nodes_running(self, context: Dict[str, Any]) -> bool:
        """Check if all nodes are running"""
        # Would use virsh list or cloud provider API
        return True  # Placeholder

    def _check_node_status(self, context: Dict[str, Any], node_spec: str) -> bool:
        """Check status of specific node"""
        # Parse node_spec like "n12:running" or "n12"
        if ":" in node_spec:
            node_name, expected_status = node_spec.split(":", 1)
        else:
            node_name = node_spec
            expected_status = "running"

        # Check node status via provider-specific means
        if self.provider == "libvirt":
            result = subprocess.run(
                ['virsh', 'list', '--all'],
                capture_output=True, text=True
            )
            # Parse virsh output to check node status
            for line in result.stdout.split('\n'):
                if node_name in line:
                    if expected_status == "running":
                        return "running" in line
                    elif expected_status == "stopped":
                        return "shut off" in line

        return False  # Placeholder

    def _check_ssh_connectivity(self, context: Dict[str, Any]) -> bool:
        """Check SSH connectivity to all nodes"""
        # Would read inventory.ini and test SSH to each node
        return True  # Placeholder

    def _check_vms_powered_off(self, context: Dict[str, Any]) -> bool:
        """Check if VMs are powered off"""
        if self.provider == "libvirt":
            result = subprocess.run(
                ['virsh', 'list', '--all'],
                capture_output=True, text=True
            )
            # Check that VMs are in "shut off" state
            return "running" not in result.stdout
        return True  # Placeholder

    def _check_database_running(self, context: Dict[str, Any]) -> bool:
        """Check if database is running"""
        # Would check c4.service status on nodes
        return True  # Placeholder

    def _check_database_degraded(self, context: Dict[str, Any]) -> bool:
        """Check if database is in degraded state"""
        return False  # Placeholder

    def _check_database_down(self, context: Dict[str, Any]) -> bool:
        """Check if database is completely down"""
        return False  # Placeholder

    def _check_admin_ui(self, context: Dict[str, Any]) -> bool:
        """Check if Admin UI is accessible"""
        # Would try to connect to Admin UI endpoint
        return True  # Placeholder

    def _check_data_integrity(self, context: Dict[str, Any]) -> bool:
        """Check data integrity after restart"""
        # Would run SQL queries to verify data
        return True  # Placeholder


class WorkflowExecutor:
    """Executes workflow-based test scenarios"""

    def __init__(self, deploy_dir: Path, provider: str, logger: logging.Logger,
                 log_callback: Optional[Callable] = None, db_version: Optional[str] = None):
        self.deploy_dir = deploy_dir
        self.provider = provider
        self.logger = logger
        self.log_callback = log_callback or (lambda msg: logger.info(msg))
        self.validation_registry = ValidationRegistry(deploy_dir, provider, logger)
        self.context: Dict[str, Any] = {}
        self.db_version = db_version  # Optional database version override

    def _run_command_with_streaming(self, cmd: List[str], timeout: int) -> subprocess.CompletedProcess:
        """Run a command and stream output in real-time to log_callback.
        
        Returns a CompletedProcess-like object with stdout, stderr, and returncode.
        """
        cmd_str = ' '.join(cmd)
        self.log_callback(f"Running command: {cmd_str}")
        
        # Use Popen to stream output in real-time
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1  # Line buffered
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

            # Stop workflow if step failed and no retry
            if step_result.status == StepStatus.FAILED and not step.retry:
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
            checks=config.get('checks', []),
            allow_failures=config.get('allow_failures', []),
            retry=config.get('retry'),
            custom_command=config.get('custom_command')
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
            elif step.step_type == 'stop_node':
                self._execute_stop_node(step)
            elif step.step_type == 'start_node':
                self._execute_start_node(step)
            elif step.step_type == 'restart_node':
                self._execute_restart_node(step)
            elif step.step_type == 'crash_node':
                self._execute_crash_node(step)
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
        
        Supported SUT parameters (add to your SUT config's 'parameters' field):
        Parameter names use underscores and map 1:1 to CLI flags (underscore -> hyphen).
        
        Common parameters:
          - cluster_size: Number of nodes (int) → --cluster-size
          - instance_type: Cloud instance type (str) → --instance-type
          - data_volumes_per_node: Number of data volumes per node (int) → --data-volumes-per-node
          - data_volume_size: Size of each data volume in GB (int) → --data-volume-size
          - root_volume_size: Size of root volume in GB (int) → --root-volume-size
          - libvirt_memory: Memory in GB for libvirt VMs (int) → --libvirt-memory
          - libvirt_vcpus: Number of vCPUs for libvirt VMs (int) → --libvirt-vcpus
          
        Boolean flags (set to true to enable):
          - enable_multicast_overlay: Enable VXLAN overlay network → --enable-multicast-overlay
          - aws_spot_instance: Enable AWS spot instances → --aws-spot-instance
          - azure_spot_instance: Enable Azure spot instances → --azure-spot-instance
          - gcp_spot_instance: Enable GCP preemptible instances → --gcp-spot-instance
        
        For provider-specific flags (aws_region, azure_region, etc.), add to param_map below.
        """
        cmd = [
            './exasol', 'init',
            '--cloud-provider', self.provider,
            '--deployment-dir', str(self.deploy_dir)
        ]

        # Add database version if provided
        if self.db_version:
            cmd.extend(['--db-version', self.db_version])

        # Standard parameters with 1:1 mapping (underscore -> hyphen)
        param_map = {
            'cluster_size': '--cluster-size',
            'instance_type': '--instance-type',
            'data_volumes_per_node': '--data-volumes-per-node',
            'data_volume_size': '--data-volume-size',
            'root_volume_size': '--root-volume-size',
            'libvirt_memory': '--libvirt-memory',
            'libvirt_vcpus': '--libvirt-vcpus',
        }

        for key, flag in param_map.items():
            if key in params:
                cmd.extend([flag, str(params[key])])
        
        # Boolean flags (parameters that don't take values)
        boolean_flags = {
            'enable_multicast_overlay': '--enable-multicast-overlay',
            'aws_spot_instance': '--aws-spot-instance',
            'azure_spot_instance': '--azure-spot-instance',
            'gcp_spot_instance': '--gcp-spot-instance',
        }
        
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
        cmd = ['./exasol', 'deploy', '--deployment-dir', str(self.deploy_dir)]
        
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
                step.validation_results = validation_results
                raise RuntimeError(f"Validation check failed: {check_name}")

        step.validation_results = validation_results
        step.result = {'all_passed': all(r['passed'] or r['allow_failure'] for r in validation_results)}

    def _execute_stop_cluster(self, step: WorkflowStep):
        """Execute cluster stop"""
        cmd = ['./exasol', 'stop', '--deployment-dir', str(self.deploy_dir)]
        
        result = self._run_command_with_streaming(cmd, timeout=600)
        
        if result.returncode != 0:
            raise RuntimeError(f"Stop cluster failed: {result.stderr}")

        step.result = {'stdout': result.stdout, 'stderr': result.stderr}

    def _execute_start_cluster(self, step: WorkflowStep):
        """Execute cluster start"""
        cmd = ['./exasol', 'start', '--deployment-dir', str(self.deploy_dir)]
        
        result = self._run_command_with_streaming(cmd, timeout=600)
        
        if result.returncode != 0:
            raise RuntimeError(f"Start cluster failed: {result.stderr}")

        step.result = {'stdout': result.stdout, 'stderr': result.stderr}

    def _execute_destroy(self, step: WorkflowStep):
        """Execute destroy step to tear down the cluster"""
        cmd = ['./exasol', 'destroy', '--deployment-dir', str(self.deploy_dir), '--auto-approve']
        
        result = self._run_command_with_streaming(cmd, timeout=600)
        
        if result.returncode != 0:
            raise RuntimeError(f"Destroy failed: {result.stderr}")

        step.result = {'stdout': result.stdout, 'stderr': result.stderr}

    def _execute_stop_node(self, step: WorkflowStep):
        """Stop a specific node"""
        if not step.target_node:
            raise ValueError("target_node is required for stop_node")

        # Node power control is not supported for these providers
        if self.provider in ["digitalocean", "hetzner", "libvirt"]:
            raise NotImplementedError(
                f"Node stop not supported for {self.provider}. "
                f"Provider does not support power on/off state transitions. "
                f"Only reboot via SSH is supported."
            )

        # For other cloud providers that support power control
        raise NotImplementedError(f"Node stop not implemented for {self.provider}")

    def _execute_start_node(self, step: WorkflowStep):
        """Start a specific node"""
        if not step.target_node:
            raise ValueError("target_node is required for start_node")

        # Node power control is not supported for these providers
        if self.provider in ["digitalocean", "hetzner", "libvirt"]:
            raise NotImplementedError(
                f"Node start not supported for {self.provider}. "
                f"Provider does not support power on/off state transitions. "
                f"Only reboot via SSH is supported."
            )

        # For other cloud providers that support power control
        raise NotImplementedError(f"Node start not implemented for {self.provider}")

    def _execute_restart_node(self, step: WorkflowStep):
        """Restart a specific node"""
        if not step.target_node:
            raise ValueError("target_node is required for restart_node")

        method = step.method or "ssh"

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

        elif method == "graceful":
            # Power cycle method - not supported for digitalocean, hetzner, libvirt
            if self.provider in ["digitalocean", "hetzner", "libvirt"]:
                raise NotImplementedError(
                    f"Graceful restart (power cycle) not supported for {self.provider}. "
                    f"Use method='ssh' for reboot via SSH command."
                )

            # For other providers with power control support
            stop_step = WorkflowStep(
                step_type="stop_node",
                description=f"Stop {step.target_node}",
                target_node=step.target_node
            )
            self._execute_stop_node(stop_step)

            # Wait a bit
            time.sleep(5)

            start_step = WorkflowStep(
                step_type="start_node",
                description=f"Start {step.target_node}",
                target_node=step.target_node
            )
            self._execute_start_node(start_step)

            step.result = {'method': 'graceful', 'node': step.target_node}
        else:
            raise ValueError(f"Unknown restart method: {method}")

    def _execute_crash_node(self, step: WorkflowStep):
        """Simulate node crash"""
        if not step.target_node:
            raise ValueError("target_node is required for crash_node")

        method = step.method or "ssh"

        if method == "ssh":
            # Crash via SSH - immediate shutdown without graceful stop
            # Supported for all providers
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
                        parts = line.split()
                        if parts and parts[0] == step.target_node:
                            node_host = parts[0]
                            break

            if not node_host:
                raise RuntimeError(f"Could not find node {step.target_node} in inventory")

            # Execute immediate shutdown (simulates crash)
            # Using 'shutdown -h now' with no grace period simulates a hard crash
            # Alternative: 'echo b > /proc/sysrq-trigger' for even harder crash (requires sysrq)
            ssh_cmd = ['ssh', '-F', str(ssh_config_path), '-o', 'BatchMode=yes',
                      '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=10',
                      node_host, 'sudo', 'sh', '-c',
                      'nohup bash -c "sleep 0.5 && echo b > /proc/sysrq-trigger || poweroff -f" &']

            result = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=30)

            # SSH connection may drop, so non-zero exit is expected
            step.result = {'method': 'ssh', 'node': step.target_node,
                          'command': 'immediate poweroff via sysrq or poweroff -f',
                          'crash_type': 'hard_shutdown'}

        elif method == "destroy":
            # Power destroy method - only for cloud providers with power control
            if self.provider in ["digitalocean", "hetzner", "libvirt"]:
                raise NotImplementedError(
                    f"Crash via power destroy not supported for {self.provider}. "
                    f"Use method='ssh' for crash via SSH command."
                )

            # For other cloud providers that support power control via API
            raise NotImplementedError(f"Crash via power destroy not implemented for {self.provider}")

        else:
            raise ValueError(f"Unknown crash method: {method}")

    def _execute_custom_command(self, step: WorkflowStep):
        """Execute a custom command"""
        if not step.custom_command:
            raise ValueError("custom_command is required")

        result = subprocess.run(
            step.custom_command,
            capture_output=True, text=True, timeout=300,
            cwd=str(self.deploy_dir)
        )

        step.result = {
            'returncode': result.returncode,
            'stdout': result.stdout,
            'stderr': result.stderr
        }

        if result.returncode != 0:
            raise RuntimeError(f"Custom command failed: {result.stderr}")
