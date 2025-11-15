#!/usr/bin/env python3
"""
Unit tests for SSH Validation Framework

Tests all SSH validation capabilities without requiring actual cloud resources.
Uses mock data and dry-run execution to validate framework functionality.
"""

import unittest
import tempfile
import json
import getpass
import uuid
from pathlib import Path
from unittest.mock import patch, MagicMock
from ssh_validator import SSHValidator, SSHCommand, SSHValidationResult


class TestSSHValidator(unittest.TestCase):
    """Test cases for SSH validation framework."""
    
    def setUp(self):
        """Set up test environment."""
        # Create user-specific temp directory
        username = getpass.getuser()
        test_id = str(uuid.uuid4())[:8]
        self.temp_dir = Path(tempfile.mkdtemp(prefix=f"exasol_test_{username}_{test_id}_"))
        self.deployment_dir = self.temp_dir / "test-deployment"
        self.deployment_dir.mkdir()
        
        # Create mock inventory file
        inventory_content = """
[exasol_nodes]
exasol-node-1 ansible_host=192.168.1.10
exasol-node-2 ansible_host=192.168.1.11

[exasol_data]
exasol-node-1 ansible_host=192.168.1.10
exasol-node-2 ansible_host=192.168.1.11

[exasol_meta]
exasol-node-1 ansible_host=192.168.1.10
"""
        inventory_file = self.deployment_dir / "inventory.ini"
        inventory_file.write_text(inventory_content.strip())
        
        # Create mock SSH key file
        ssh_key_file = self.deployment_dir / "exasol-cluster-key"
        ssh_key_file.write_text("mock-ssh-key-content")
        
        self.validator = SSHValidator(self.deployment_dir, dry_run=True)
    
    def tearDown(self):
        """Clean up test environment."""
        import shutil
        shutil.rmtree(self.temp_dir)
    
    def test_inventory_loading(self):
        """Test inventory file parsing."""
        inventory = self.validator.inventory
        
        self.assertIn('exasol_nodes', inventory)
        self.assertIn('exasol_data', inventory)
        self.assertIn('exasol_meta', inventory)
        self.assertIn('all_hosts', inventory)
        
        self.assertEqual(len(inventory['exasol_nodes']), 2)
        self.assertEqual(len(inventory['exasol_meta']), 1)
        self.assertIn('exasol-node-1', inventory['exasol_nodes'])
        self.assertIn('exasol-node-2', inventory['exasol_nodes'])
    
    def test_ssh_config_loading(self):
        """Test SSH configuration loading."""
        ssh_config = self.validator.ssh_config
        
        self.assertIn('key_file', ssh_config)
        self.assertIn('user', ssh_config)
        self.assertIn('port', ssh_config)
        self.assertEqual(ssh_config['user'], 'exasol')
        self.assertEqual(ssh_config['port'], 22)
    
    def test_mock_inventory_creation(self):
        """Test mock inventory creation when no inventory file exists."""
        # Create user-specific temp directory
        username = getpass.getuser()
        test_id = str(uuid.uuid4())[:8]
        temp_dir = Path(tempfile.mkdtemp(prefix=f"exasol_test_{username}_{test_id}_"))
        deployment_dir = temp_dir / "no-inventory"
        deployment_dir.mkdir()
        
        try:
            validator = SSHValidator(deployment_dir, dry_run=True)
            inventory = validator.inventory
            
            # Should create mock inventory
            self.assertIn('exasol_nodes', inventory)
            self.assertEqual(len(inventory['exasol_nodes']), 2)
            
        finally:
            import shutil
            shutil.rmtree(temp_dir)
    
    def test_ssh_command_creation(self):
        """Test SSH command creation."""
        ssh_cmd = self.validator._create_ssh_command("exasol-node-1", "ls -la")
        
        expected_elements = [
            'ssh',
            '-i', str(self.deployment_dir / 'exasol-cluster-key'),
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'ConnectTimeout=30',
            '-o', 'BatchMode=yes',
            'exasol@exasol-node-1',
            'ls -la'
        ]
        
        self.assertEqual(ssh_cmd, expected_elements)
    
    def test_dry_run_execution(self):
        """Test dry-run command execution."""
        validation = SSHCommand(
            command="test command",
            description="Test validation"
        )
        
        ssh_cmd = ["ssh", "test"]
        result = self.validator._execute_command(ssh_cmd, validation)
        
        self.assertTrue(result.success)
        self.assertTrue(result.dry_run)
        self.assertIn("DRY_RUN:", result.stdout)
        self.assertIsNone(result.exit_code)
        self.assertIsNone(result.stderr)
    
    def test_validate_symlinks_dry_run(self):
        """Test symlink validation in dry-run mode."""
        results = self.validator.validate_symlinks()
        
        # Should return results for all nodes
        self.assertEqual(len(results), 2)
        
        for result in results:
            self.assertTrue(result.success)
            self.assertTrue(result.dry_run)
            self.assertIn("symlinks", result.description)
            self.assertIn("DRY_RUN:", result.stdout)
    
    def test_validate_volume_sizes_dry_run(self):
        """Test volume size validation in dry-run mode."""
        results = self.validator.validate_volume_sizes(100)
        
        self.assertEqual(len(results), 2)
        
        for result in results:
            self.assertTrue(result.success)
            self.assertTrue(result.dry_run)
            self.assertIn("volume size", result.description)
    
    def test_validate_services_dry_run(self):
        """Test service validation in dry-run mode."""
        results = self.validator.validate_services()
        
        self.assertEqual(len(results), 2)
        
        for result in results:
            self.assertTrue(result.success)
            self.assertTrue(result.dry_run)
            self.assertIn("service status", result.description)
    
    def test_validate_database_installation_dry_run(self):
        """Test database installation validation in dry-run mode."""
        results = self.validator.validate_database_installation()
        
        self.assertEqual(len(results), 2)
        
        for result in results:
            self.assertTrue(result.success)
            self.assertTrue(result.dry_run)
            self.assertIn("database installation", result.description)
    
    def test_validate_cluster_connectivity_dry_run(self):
        """Test cluster connectivity validation in dry-run mode."""
        results = self.validator.validate_cluster_connectivity()
        
        # Should test connectivity from primary to secondary node
        self.assertEqual(len(results), 1)  # Only one secondary node
        
        for result in results:
            self.assertTrue(result.success)
            self.assertTrue(result.dry_run)
            self.assertIn("connectivity", result.description)
    
    def test_validate_system_resources_dry_run(self):
        """Test system resources validation in dry-run mode."""
        results = self.validator.validate_system_resources()
        
        # Should test CPU and memory for each node
        self.assertEqual(len(results), 4)  # 2 nodes * 2 checks each
        
        for result in results:
            self.assertTrue(result.success)
            self.assertTrue(result.dry_run)
            self.assertTrue("CPU" in result.description or "memory" in result.description)
    
    def test_execution_plan_generation(self):
        """Test execution plan generation."""
        plan = self.validator.get_execution_plan()
        
        self.assertIn('inventory', plan)
        self.assertIn('ssh_config', plan)
        self.assertIn('validations', plan)
        
        # Check all validation types are included
        validation_names = [v['name'] for v in plan['validations']]
        expected_validations = [
            'symlinks', 'volume_sizes', 'services', 
            'database', 'connectivity', 'system_resources'
        ]
        
        for expected in expected_validations:
            self.assertIn(expected, validation_names)
        
        # Check that each validation has commands and hosts
        for validation in plan['validations']:
            self.assertIn('commands', validation)
            self.assertIn('hosts', validation)
            self.assertGreater(len(validation['commands']), 0)
            self.assertGreater(len(validation['hosts']), 0)
    
    def test_save_execution_plan(self):
        """Test saving execution plan to file."""
        output_file = self.temp_dir / "execution_plan.json"
        
        self.validator.save_execution_plan(output_file)
        
        self.assertTrue(output_file.exists())
        
        # Load and verify saved plan
        with open(output_file, 'r') as f:
            saved_plan = json.load(f)
        
        self.assertIn('inventory', saved_plan)
        self.assertIn('ssh_config', saved_plan)
        self.assertIn('validations', saved_plan)
    
    def test_results_summary_empty(self):
        """Test results summary when no results exist."""
        summary = self.validator.get_results_summary()
        
        self.assertEqual(summary['status'], 'no_results')
        self.assertIn('No validations executed yet', summary['message'])
    
    def test_results_summary_with_results(self):
        """Test results summary with validation results."""
        # Add some mock results
        self.validator.results = [
            SSHValidationResult(
                command="test1",
                description="Test 1",
                success=True,
                dry_run=True
            ),
            SSHValidationResult(
                command="test2",
                description="Test 2",
                success=False,
                dry_run=True
            )
        ]
        
        summary = self.validator.get_results_summary()
        
        self.assertEqual(summary['total_validations'], 2)
        self.assertEqual(summary['passed'], 1)
        self.assertEqual(summary['failed'], 1)
        self.assertEqual(summary['success_rate'], 0.5)
        self.assertTrue(summary['dry_run'])
        self.assertEqual(summary['hosts_tested'], 2)
        self.assertIn('results', summary)


class TestSSHCommand(unittest.TestCase):
    """Test cases for SSHCommand dataclass."""
    
    def test_ssh_command_creation(self):
        """Test SSHCommand creation with default values."""
        cmd = SSHCommand(
            command="ls -la",
            description="List files"
        )
        
        self.assertEqual(cmd.command, "ls -la")
        self.assertEqual(cmd.description, "List files")
        self.assertEqual(cmd.expected_exit_code, 0)
        self.assertEqual(cmd.expected_patterns, [])
        self.assertEqual(cmd.timeout_seconds, 30)
    
    def test_ssh_command_with_patterns(self):
        """Test SSHCommand creation with expected patterns."""
        patterns = ["success", "completed"]
        cmd = SSHCommand(
            command="test",
            description="Test command",
            expected_patterns=patterns
        )
        
        self.assertEqual(cmd.expected_patterns, patterns)


class TestSSHValidationResult(unittest.TestCase):
    """Test cases for SSHValidationResult dataclass."""
    
    def test_validation_result_creation(self):
        """Test SSHValidationResult creation."""
        result = SSHValidationResult(
            command="ssh test",
            description="Test SSH",
            success=True,
            exit_code=0,
            stdout="output",
            stderr="errors",
            execution_time=1.5,
            dry_run=False
        )
        
        self.assertEqual(result.command, "ssh test")
        self.assertEqual(result.description, "Test SSH")
        self.assertTrue(result.success)
        self.assertEqual(result.exit_code, 0)
        self.assertEqual(result.stdout, "output")
        self.assertEqual(result.stderr, "errors")
        self.assertEqual(result.execution_time, 1.5)
        self.assertFalse(result.dry_run)


if __name__ == '__main__':
    unittest.main()