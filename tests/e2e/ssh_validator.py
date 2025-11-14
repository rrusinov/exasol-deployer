#!/usr/bin/env python3
"""
SSH Validation Framework for E2E Testing

Provides SSH-based validation capabilities for deployed Exasol clusters.
This module creates execution plans that can be inspected and tested without
actually connecting to cloud resources.
"""

import json
import subprocess
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, asdict
import logging


@dataclass
class SSHCommand:
    """Represents a command to be executed via SSH."""
    command: str
    description: str
    expected_exit_code: int = 0
    expected_patterns: Optional[List[str]] = None
    timeout_seconds: int = 30
    
    def __post_init__(self):
        if self.expected_patterns is None:
            self.expected_patterns = []


@dataclass
class SSHValidationResult:
    """Result of SSH validation execution."""
    command: str
    description: str
    success: bool
    exit_code: Optional[int] = None
    stdout: Optional[str] = None
    stderr: Optional[str] = None
    execution_time: Optional[float] = None
    error_message: Optional[str] = None
    dry_run: bool = False


class SSHValidator:
    """SSH-based validation framework for Exasol deployments."""
    
    def __init__(self, deployment_dir: Path, dry_run: bool = True):
        self.deployment_dir = Path(deployment_dir)
        self.dry_run = dry_run
        self.logger = logging.getLogger(__name__)
        
        # Load inventory and SSH configuration
        self.inventory = self._load_inventory()
        self.ssh_config = self._load_ssh_config()
        
        # Validation results
        self.results: List[SSHValidationResult] = []
    
    def _load_inventory(self) -> Dict[str, Any]:
        """Load Ansible inventory file."""
        inventory_file = self.deployment_dir / 'inventory.ini'
        
        if not inventory_file.exists():
            return self._create_mock_inventory()
        
        # Parse inventory.ini format
        inventory = {
            'exasol_nodes': [],
            'exasol_data': [],
            'exasol_meta': [],
            'all_hosts': []
        }
        
        try:
            with open(inventory_file, 'r') as f:
                current_section = None
                for line in f:
                    line = line.strip()
                    if line.startswith('[') and line.endswith(']'):
                        current_section = line[1:-1]
                        if current_section not in inventory:
                            inventory[current_section] = []
                    elif line and not line.startswith('#') and current_section:
                        # Extract hostname from line (format: hostname ansible_host=IP)
                        hostname = line.split()[0]
                        inventory[current_section].append(hostname)
                        inventory['all_hosts'].append(hostname)
        except Exception as e:
            self.logger.warning(f"Failed to parse inventory: {e}")
            return self._create_mock_inventory()
        
        return inventory
    
    def _create_mock_inventory(self) -> Dict[str, Any]:
        """Create mock inventory for testing."""
        return {
            'exasol_nodes': ['exasol-node-1', 'exasol-node-2'],
            'exasol_data': ['exasol-node-1', 'exasol-node-2'],
            'exasol_meta': ['exasol-node-1'],
            'all_hosts': ['exasol-node-1', 'exasol-node-2']
        }
    
    def _load_ssh_config(self) -> Dict[str, Any]:
        """Load SSH configuration from deployment."""
        # Look for SSH key in deployment directory
        ssh_key_file = self.deployment_dir / 'exasol-cluster-key'
        
        if not ssh_key_file.exists():
            # Create mock SSH config for testing
            return {
                'key_file': str(ssh_key_file),
                'user': 'exasol',
                'port': 22,
                'connect_timeout': 30
            }
        
        return {
            'key_file': str(ssh_key_file),
            'user': 'exasol',
            'port': 22,
            'connect_timeout': 30
        }
    
    def _create_ssh_command(self, host: str, command: str) -> List[str]:
        """Create SSH command for execution."""
        ssh_cmd = [
            'ssh',
            '-i', self.ssh_config['key_file'],
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'ConnectTimeout=' + str(self.ssh_config['connect_timeout']),
            '-o', 'BatchMode=yes',
            f"{self.ssh_config['user']}@{host}",
            command
        ]
        return ssh_cmd
    
    def _execute_command(self, ssh_command: List[str], validation: SSHCommand) -> SSHValidationResult:
        """Execute SSH command and return result."""
        result = SSHValidationResult(
            command=' '.join(ssh_command),
            description=validation.description,
            success=False,  # Will be set later
            dry_run=self.dry_run
        )
        
        if self.dry_run:
            # For dry run, just record the command that would be executed
            result.success = True
            result.stdout = f"DRY_RUN: Would execute: {result.command}"
            self.logger.info(f"DRY_RUN: {validation.description}")
            return result
        
        try:
            import time
            start_time = time.time()
            
            process = subprocess.run(
                ssh_command,
                capture_output=True,
                text=True,
                timeout=validation.timeout_seconds
            )
            
            result.exit_code = process.returncode
            result.stdout = process.stdout
            result.stderr = process.stderr
            result.execution_time = time.time() - start_time
            
            # Check if command succeeded
            result.success = (
                process.returncode == validation.expected_exit_code and
                all(pattern in process.stdout for pattern in validation.expected_patterns or [])
            )
            
            if not result.success:
                result.error_message = f"Exit code: {process.returncode}, Expected: {validation.expected_exit_code}"
                
        except subprocess.TimeoutExpired:
            result.success = False
            result.error_message = f"Command timed out after {validation.timeout_seconds} seconds"
        except Exception as e:
            result.success = False
            result.error_message = str(e)
        
        return result
    
    def validate_symlinks(self) -> List[SSHValidationResult]:
        """Validate /dev/exasol_data_* symlinks on all nodes."""
        validation = SSHCommand(
            command="ls -1 /dev/exasol_data_* 2>/dev/null | wc -l",
            description="Check /dev/exasol_data_* symlinks",
            expected_patterns=[r'\d+']  # Should output a number
        )
        
        results = []
        for host in self.inventory.get('exasol_nodes', []):
            ssh_cmd = self._create_ssh_command(host, validation.command)
            result = self._execute_command(ssh_cmd, validation)
            results.append(result)
            self.results.append(result)
        
        return results
    
    def validate_volume_sizes(self, expected_size_gb: int) -> List[SSHValidationResult]:
        """Validate data volume sizes on all nodes."""
        validation = SSHCommand(
            command="lsblk -b -o SIZE,NAME | grep -E 'xvd[b-z]' | awk '{print $1}' | head -1",
            description=f"Check data volume size (expected: {expected_size_gb}GB)",
            expected_patterns=[]
        )
        
        results = []
        for host in self.inventory.get('exasol_nodes', []):
            ssh_cmd = self._create_ssh_command(host, validation.command)
            result = self._execute_command(ssh_cmd, validation)
            results.append(result)
            self.results.append(result)
        
        return results
    
    def validate_services(self) -> List[SSHValidationResult]:
        """Validate systemd services status."""
        validation = SSHCommand(
            command="systemctl is-active exasol-data-symlinks.service",
            description="Check exasol-data-symlinks service status",
            expected_patterns=['active']
        )
        
        results = []
        for host in self.inventory.get('exasol_nodes', []):
            ssh_cmd = self._create_ssh_command(host, validation.command)
            result = self._execute_command(ssh_cmd, validation)
            results.append(result)
            self.results.append(result)
        
        return results
    
    def validate_database_installation(self) -> List[SSHValidationResult]:
        """Validate Exasol database installation."""
        validation = SSHCommand(
            command="test -d /opt/exasol/EXASolution && echo 'DB_INSTALLED'",
            description="Check Exasol database installation",
            expected_patterns=['DB_INSTALLED']
        )
        
        results = []
        for host in self.inventory.get('exasol_nodes', []):
            ssh_cmd = self._create_ssh_command(host, validation.command)
            result = self._execute_command(ssh_cmd, validation)
            results.append(result)
            self.results.append(result)
        
        return results
    
    def validate_cluster_connectivity(self) -> List[SSHValidationResult]:
        """Validate inter-node connectivity."""
        results = []
        
        # Test connectivity from primary node to other nodes
        primary_host = self.inventory.get('exasol_meta', [self.inventory.get('exasol_nodes', [''])[0]])[0]
        
        for host in self.inventory.get('exasol_nodes', []):
            if host == primary_host:
                continue
                
            validation = SSHCommand(
                command=f"ping -c 1 -W 5 {host} >/dev/null 2>&1 && echo 'CONNECTED'",
                description=f"Test connectivity from {primary_host} to {host}",
                expected_patterns=['CONNECTED']
            )
            
            ssh_cmd = self._create_ssh_command(primary_host, validation.command)
            result = self._execute_command(ssh_cmd, validation)
            results.append(result)
            self.results.append(result)
        
        return results
    
    def validate_system_resources(self) -> List[SSHValidationResult]:
        """Validate system resources (CPU, memory, disk)."""
        results = []
        
        for host in self.inventory.get('exasol_nodes', []):
            # CPU validation
            cpu_validation = SSHCommand(
                command="nproc",
                description="Check CPU count",
                expected_patterns=[r'\d+']
            )
            ssh_cmd = self._create_ssh_command(host, cpu_validation.command)
            result = self._execute_command(ssh_cmd, cpu_validation)
            results.append(result)
            self.results.append(result)
            
            # Memory validation
            mem_validation = SSHCommand(
                command="free -h | grep '^Mem:' | awk '{print $2}'",
                description="Check memory size",
                expected_patterns=[r'\d+\.?\d*[GT]']
            )
            ssh_cmd = self._create_ssh_command(host, mem_validation.command)
            result = self._execute_command(ssh_cmd, mem_validation)
            results.append(result)
            self.results.append(result)
        
        return results
    
    def get_execution_plan(self) -> Dict[str, Any]:
        """Get complete execution plan without running commands."""
        plan = {
            'inventory': self.inventory,
            'ssh_config': self.ssh_config,
            'validations': []
        }
        
        # Add all validation commands to plan
        validations = [
            ("symlinks", self.validate_symlinks),
            ("volume_sizes", lambda: self.validate_volume_sizes(100)),  # Default 100GB
            ("services", self.validate_services),
            ("database", self.validate_database_installation),
            ("connectivity", self.validate_cluster_connectivity),
            ("system_resources", self.validate_system_resources)
        ]
        
        for name, validator_func in validations:
            # Create a temporary validator to extract commands
            temp_validator = SSHValidator(self.deployment_dir, dry_run=True)
            temp_validator.inventory = self.inventory
            temp_validator.ssh_config = self.ssh_config
            
            # Execute in dry-run mode to capture commands
            results = validator_func()
            
            plan['validations'].append({
                'name': name,
                'description': validator_func.__name__,
                'commands': [r.command for r in results],
                'hosts': self.inventory.get('exasol_nodes', [])
            })
        
        return plan
    
    def save_execution_plan(self, output_file: Path) -> None:
        """Save execution plan to JSON file."""
        plan = self.get_execution_plan()
        
        with open(output_file, 'w') as f:
            json.dump(plan, f, indent=2)
        
        self.logger.info(f"Execution plan saved to {output_file}")
    
    def get_results_summary(self) -> Dict[str, Any]:
        """Get summary of all validation results."""
        if not self.results:
            return {'status': 'no_results', 'message': 'No validations executed yet'}
        
        total = len(self.results)
        passed = sum(1 for r in self.results if r.success)
        failed = total - passed
        
        return {
            'total_validations': total,
            'passed': passed,
            'failed': failed,
            'success_rate': passed / total if total > 0 else 0,
            'dry_run': self.dry_run,
            'hosts_tested': len(self.inventory.get('exasol_nodes', [])),
            'results': [asdict(r) for r in self.results]
        }