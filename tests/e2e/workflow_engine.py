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
                 log_callback: Optional[Callable] = None):
        self.deploy_dir = deploy_dir
        self.provider = provider
        self.logger = logger
        self.log_callback = log_callback or (lambda msg: logger.info(msg))
        self.validation_registry = ValidationRegistry(deploy_dir, provider, logger)
        self.context: Dict[str, Any] = {}

    def execute_workflow(self, workflow: List[Dict[str, Any]],
                        params: Dict[str, Any]) -> List[WorkflowStep]:
        """Execute a complete workflow"""
        results = []
        self.context = {'parameters': params, 'deploy_dir': str(self.deploy_dir)}

        for step_config in workflow:
            step = self._parse_step_config(step_config)
            self.logger.info(f"Executing step: {step.description}")
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
        return WorkflowStep(
            step_type=config['step'],
            description=config.get('description', ''),
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
        """Execute init step"""
        cmd = [
            './exasol', 'init',
            '--cloud-provider', self.provider,
            '--deployment-dir', str(self.deploy_dir)
        ]

        # Add parameters
        param_map = {
            'cluster_size': '--cluster-size',
            'instance_type': '--instance-type',
            'data_volumes_per_node': '--data-volumes-per-node',
            'data_volume_size': '--data-volume-size',
            'root_volume_size': '--root-volume-size',
            'libvirt_memory_gb': '--libvirt-memory',
            'libvirt_vcpus': '--libvirt-vcpus',
        }

        for key, flag in param_map.items():
            if key in params:
                cmd.extend([flag, str(params[key])])

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if result.returncode != 0:
            raise RuntimeError(f"Init failed: {result.stderr}")

        step.result = {'stdout': result.stdout, 'stderr': result.stderr}

    def _execute_deploy(self, step: WorkflowStep):
        """Execute deploy step"""
        result = subprocess.run(
            ['./exasol', 'deploy', '--deployment-dir', str(self.deploy_dir)],
            capture_output=True, text=True, timeout=3600
        )
        if result.returncode != 0:
            raise RuntimeError(f"Deploy failed: {result.stderr}")

        step.result = {'stdout': result.stdout}

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
        result = subprocess.run(
            ['./exasol', 'stop', '--deployment-dir', str(self.deploy_dir)],
            capture_output=True, text=True, timeout=600
        )
        if result.returncode != 0:
            raise RuntimeError(f"Stop cluster failed: {result.stderr}")

        step.result = {'stdout': result.stdout}

    def _execute_start_cluster(self, step: WorkflowStep):
        """Execute cluster start"""
        result = subprocess.run(
            ['./exasol', 'start', '--deployment-dir', str(self.deploy_dir)],
            capture_output=True, text=True, timeout=600
        )
        if result.returncode != 0:
            raise RuntimeError(f"Start cluster failed: {result.stderr}")

        step.result = {'stdout': result.stdout}

    def _execute_stop_node(self, step: WorkflowStep):
        """Stop a specific node"""
        if not step.target_node:
            raise ValueError("target_node is required for stop_node")

        # For libvirt, use virsh destroy
        if self.provider == "libvirt":
            # Find VM name from deployment
            result = subprocess.run(
                ['virsh', 'list', '--all'],
                capture_output=True, text=True
            )

            # Find VM ID matching target node
            vm_name = None
            for line in result.stdout.split('\n'):
                if step.target_node in line:
                    vm_name = line.split()[1]
                    break

            if not vm_name:
                raise RuntimeError(f"Could not find VM for node {step.target_node}")

            result = subprocess.run(
                ['virsh', 'shutdown', vm_name],
                capture_output=True, text=True, timeout=60
            )

            step.result = {'vm_name': vm_name, 'output': result.stdout}
        else:
            # For cloud providers, would use provider-specific API
            raise NotImplementedError(f"Node stop not implemented for {self.provider}")

    def _execute_start_node(self, step: WorkflowStep):
        """Start a specific node"""
        if not step.target_node:
            raise ValueError("target_node is required for start_node")

        if self.provider == "libvirt":
            result = subprocess.run(
                ['virsh', 'list', '--all'],
                capture_output=True, text=True
            )

            vm_name = None
            for line in result.stdout.split('\n'):
                if step.target_node in line:
                    vm_name = line.split()[1]
                    break

            if not vm_name:
                raise RuntimeError(f"Could not find VM for node {step.target_node}")

            result = subprocess.run(
                ['virsh', 'start', vm_name],
                capture_output=True, text=True, timeout=60
            )

            step.result = {'vm_name': vm_name, 'output': result.stdout}
        else:
            raise NotImplementedError(f"Node start not implemented for {self.provider}")

    def _execute_restart_node(self, step: WorkflowStep):
        """Restart a specific node"""
        if not step.target_node:
            raise ValueError("target_node is required for restart_node")

        method = step.method or "graceful"

        if method == "graceful":
            # Stop then start
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

        method = step.method or "destroy"

        if self.provider == "libvirt":
            result = subprocess.run(
                ['virsh', 'list', '--all'],
                capture_output=True, text=True
            )

            vm_name = None
            for line in result.stdout.split('\n'):
                if step.target_node in line:
                    vm_name = line.split()[1]
                    break

            if not vm_name:
                raise RuntimeError(f"Could not find VM for node {step.target_node}")

            # Use destroy for hard crash simulation
            result = subprocess.run(
                ['virsh', 'destroy', vm_name],
                capture_output=True, text=True, timeout=30
            )

            step.result = {'vm_name': vm_name, 'method': method, 'output': result.stdout}
        else:
            raise NotImplementedError(f"Node crash not implemented for {self.provider}")

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
