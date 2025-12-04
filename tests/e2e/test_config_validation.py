#!/usr/bin/env python3
"""
Unit Tests for Configuration Validation and Documentation Consistency

Tests that:
1. Workflow configurations are valid
2. SUT configurations are valid  
3. Documentation matches implemented features
4. Schema definitions are consistent
"""

import json
import re
import sys
import unittest
from pathlib import Path
from typing import Dict, List, Set

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from config_schema import (
    SUPPORTED_PROVIDERS,
    WORKFLOW_STEPS,
    HEALTH_CHECK_COMPONENTS,
    VALIDATION_CHECK_PATTERNS,
    VALID_CLUSTER_STATUSES,
    SUT_PARAMETERS,
    validate_workflow_step,
    validate_validation_check,
    validate_sut_parameters,
)


class TestConfigSchema(unittest.TestCase):
    """Test configuration schema definitions"""
    
    def test_workflow_steps_defined(self):
        """Test that all workflow steps have schema definitions"""
        required_steps = [
            'init', 'deploy', 'validate', 'stop_cluster', 'start_cluster',
            'stop_node', 'start_node', 'restart_node', 'crash_node',
            'custom_command', 'destroy'
        ]
        
        for step in required_steps:
            self.assertIn(step, WORKFLOW_STEPS, f"Step {step} missing from WORKFLOW_STEPS")
            self.assertIsNotNone(WORKFLOW_STEPS[step].description)
            self.assertIsInstance(WORKFLOW_STEPS[step].required_fields, list)
            self.assertIsInstance(WORKFLOW_STEPS[step].optional_fields, list)
    
    def test_providers_defined(self):
        """Test that all supported providers are defined"""
        expected_providers = {'aws', 'azure', 'gcp', 'digitalocean', 'hetzner', 'libvirt'}
        self.assertEqual(SUPPORTED_PROVIDERS, expected_providers)
    
    def test_health_components_defined(self):
        """Test that health check components are defined"""
        required_components = ['ssh', 'adminui', 'database', 'cos_ssh']
        
        for component in required_components:
            self.assertIn(component, HEALTH_CHECK_COMPONENTS)
    
    def test_sut_parameters_have_cli_flags(self):
        """Test that all SUT parameters have CLI flag mappings"""
        for param_name, param_info in SUT_PARAMETERS.items():
            self.assertIn('cli_flag', param_info)
            self.assertTrue(param_info['cli_flag'].startswith('--'))
            
            # Verify underscore to hyphen mapping
            expected_flag = '--' + param_name.replace('_', '-')
            self.assertEqual(param_info['cli_flag'], expected_flag,
                           f"Parameter {param_name} should map to {expected_flag}")


class TestWorkflowValidation(unittest.TestCase):
    """Test workflow configuration validation"""
    
    @classmethod
    def setUpClass(cls):
        """Load workflow configurations"""
        cls.test_dir = Path(__file__).parent
        cls.workflow_dir = cls.test_dir / 'configs' / 'workflow'
        cls.workflows = {}
        
        if cls.workflow_dir.exists():
            for workflow_file in cls.workflow_dir.glob('*.json'):
                with open(workflow_file) as f:
                    cls.workflows[workflow_file.stem] = json.load(f)
    
    def test_workflow_files_exist(self):
        """Test that expected workflow files exist"""
        expected = ['simple', 'basic', 'enhanced']
        
        for name in expected:
            self.assertIn(name, self.workflows, f"Missing workflow file: {name}.json")
    
    def test_workflow_steps_valid(self):
        """Test that all workflow steps are valid"""
        for workflow_name, workflow_config in self.workflows.items():
            self.assertIn('steps', workflow_config, f"{workflow_name}: missing 'steps' field")
            
            steps = workflow_config['steps']
            self.assertIsInstance(steps, list, f"{workflow_name}: 'steps' must be a list")
            self.assertGreater(len(steps), 0, f"{workflow_name}: 'steps' must not be empty")
            
            for i, step in enumerate(steps):
                errors = validate_workflow_step(step, 'libvirt')  # Use libvirt as baseline
                self.assertEqual([], errors,
                               f"{workflow_name} step {i}: {', '.join(errors)}")
    
    def test_validation_checks_valid(self):
        """Test that all validation checks in workflows are valid"""
        for workflow_name, workflow_config in self.workflows.items():
            for i, step in enumerate(workflow_config.get('steps', [])):
                if step.get('step') == 'validate':
                    checks = step.get('checks', [])
                    for check in checks:
                        errors = validate_validation_check(check)
                        self.assertEqual([], errors,
                                       f"{workflow_name} step {i} check '{check}': {', '.join(errors)}")


class TestSUTValidation(unittest.TestCase):
    """Test SUT configuration validation"""
    
    @classmethod
    def setUpClass(cls):
        """Load SUT configurations"""
        cls.test_dir = Path(__file__).parent
        cls.sut_dir = cls.test_dir / 'configs' / 'sut'
        cls.suts = {}
        
        if cls.sut_dir.exists():
            for sut_file in cls.sut_dir.glob('*.json'):
                with open(sut_file) as f:
                    cls.suts[sut_file.stem] = json.load(f)
    
    def test_sut_files_exist(self):
        """Test that SUT configuration files exist"""
        # At least some SUT files should exist
        self.assertGreater(len(self.suts), 0, "No SUT configuration files found")
    
    def test_sut_required_fields(self):
        """Test that SUTs have required fields"""
        for sut_name, sut_config in self.suts.items():
            self.assertIn('provider', sut_config, f"{sut_name}: missing 'provider' field")
            self.assertIn('parameters', sut_config, f"{sut_name}: missing 'parameters' field")
            
            provider = sut_config['provider']
            self.assertIn(provider, SUPPORTED_PROVIDERS,
                         f"{sut_name}: unknown provider '{provider}'")
    
    def test_sut_parameters_valid(self):
        """Test that SUT parameters are valid for their providers"""
        for sut_name, sut_config in self.suts.items():
            provider = sut_config.get('provider')
            if not provider:
                continue
            
            parameters = sut_config.get('parameters', {})
            errors = validate_sut_parameters(parameters, provider)
            self.assertEqual([], errors,
                           f"{sut_name}: {', '.join(errors)}")
    
    def test_sut_no_redundant_name_field(self):
        """Test that SUTs don't have redundant sut_name field (should use filename)"""
        for sut_name, sut_config in self.suts.items():
            if 'sut_name' in sut_config:
                # If present, it should match the filename
                self.assertEqual(sut_config['sut_name'], sut_name,
                               f"{sut_name}: sut_name field '{sut_config['sut_name']}' "
                               f"should match filename or be removed")


class TestDocumentationConsistency(unittest.TestCase):
    """Test that documentation matches implementation"""
    
    @classmethod
    def setUpClass(cls):
        """Load documentation"""
        cls.test_dir = Path(__file__).parent
        cls.docs_dir = cls.test_dir.parent.parent / 'docs'
        cls.readme_file = cls.docs_dir / 'E2E-README.md'
        
        if cls.readme_file.exists():
            with open(cls.readme_file) as f:
                cls.readme_content = f.read()
        else:
            cls.readme_content = ""
    
    def test_readme_exists(self):
        """Test that E2E README exists"""
        self.assertTrue(self.readme_file.exists(), "E2E-README.md not found")
    
    def test_workflow_steps_documented(self):
        """Test that all workflow steps are documented"""
        if not self.readme_content:
            self.skipTest("README not found")
        
        for step_name in WORKFLOW_STEPS.keys():
            # Check if step is mentioned in documentation
            # Look for patterns like "#### 1. `init`" or "### `init` -"
            pattern = rf'[`\'"]?{step_name}[`\'"]?'
            self.assertRegex(self.readme_content, pattern,
                           f"Workflow step '{step_name}' not documented in README")
    
    def test_providers_documented(self):
        """Test that all providers are documented"""
        if not self.readme_content:
            self.skipTest("README not found")
        
        for provider in SUPPORTED_PROVIDERS:
            self.assertIn(provider, self.readme_content.lower(),
                         f"Provider '{provider}' not documented in README")
    
    def test_health_components_documented(self):
        """Test that health check components are documented"""
        if not self.readme_content:
            self.skipTest("README not found")
        
        for component in HEALTH_CHECK_COMPONENTS.keys():
            # Should be documented in health check examples
            self.assertIn(component, self.readme_content,
                         f"Health component '{component}' not documented in README")
    
    def test_sut_parameters_documented(self):
        """Test that SUT parameters are documented"""
        if not self.readme_content:
            self.skipTest("README not found")
        
        # Check key parameters are mentioned
        key_params = ['cluster_size', 'instance_type', 'enable_multicast_overlay',
                     'libvirt_memory', 'libvirt_vcpus']
        
        for param in key_params:
            self.assertIn(param, self.readme_content,
                         f"Parameter '{param}' not documented in README")
    
    def test_validation_patterns_documented(self):
        """Test that validation check patterns are documented"""
        if not self.readme_content:
            self.skipTest("README not found")
        
        # Check that cluster_status and health_status patterns are documented
        self.assertIn('cluster_status==', self.readme_content,
                     "cluster_status pattern not documented")
        self.assertIn('health_status[', self.readme_content,
                     "health_status pattern not documented")


class TestStepValidation(unittest.TestCase):
    """Test individual step validation functions"""
    
    def test_valid_init_step(self):
        """Test validation of valid init step"""
        step = {"step": "init"}
        errors = validate_workflow_step(step, "aws")
        self.assertEqual([], errors)
    
    def test_valid_validate_step(self):
        """Test validation of valid validate step"""
        step = {
            "step": "validate",
            "checks": ["cluster_status==database_ready"],
            "description": "Test validation"
        }
        errors = validate_workflow_step(step, "aws")
        self.assertEqual([], errors)
    
    def test_invalid_step_missing_required(self):
        """Test validation catches missing required fields"""
        step = {"step": "restart_node"}  # Missing target_node
        errors = validate_workflow_step(step, "aws")
        self.assertIn("missing required field: target_node", errors[0].lower())
    
    def test_invalid_step_unknown_type(self):
        """Test validation catches unknown step types"""
        step = {"step": "invalid_step_type"}
        errors = validate_workflow_step(step, "aws")
        self.assertIn("unknown step type", errors[0].lower())


class TestCheckValidation(unittest.TestCase):
    """Test validation check validation functions"""
    
    def test_valid_cluster_status_check(self):
        """Test valid cluster status checks"""
        valid_checks = [
            "cluster_status==database_ready",
            "cluster_status==stopped",
            "cluster_status!=error",
        ]
        
        for check in valid_checks:
            errors = validate_validation_check(check)
            self.assertEqual([], errors, f"Check '{check}' should be valid")
    
    def test_valid_health_status_check(self):
        """Test valid health status checks"""
        valid_checks = [
            "health_status[*].ssh==ok",
            "health_status[n11].adminui==ok",
            "health_status[n12,n13].database!=failed",
            "health_status[*].cos_ssh==ok",
        ]
        
        for check in valid_checks:
            errors = validate_validation_check(check)
            self.assertEqual([], errors, f"Check '{check}' should be valid")
    
    def test_invalid_cluster_status_value(self):
        """Test invalid cluster status value"""
        check = "cluster_status==invalid_status"
        errors = validate_validation_check(check)
        self.assertGreater(len(errors), 0)
        self.assertIn("unknown cluster status value", errors[0].lower())
    
    def test_invalid_health_component(self):
        """Test invalid health check component"""
        check = "health_status[*].invalid_component==ok"
        errors = validate_validation_check(check)
        self.assertGreater(len(errors), 0)
        self.assertIn("unknown health check component", errors[0].lower())
    
    def test_invalid_health_value(self):
        """Test invalid health check value"""
        check = "health_status[*].ssh==invalid_value"
        errors = validate_validation_check(check)
        self.assertGreater(len(errors), 0)
        self.assertIn("unknown health check value", errors[0].lower())


class TestParameterValidation(unittest.TestCase):
    """Test SUT parameter validation functions"""
    
    def test_valid_aws_parameters(self):
        """Test valid AWS parameters"""
        params = {
            "cluster_size": 4,
            "instance_type": "t3a.xlarge",
            "data_volumes_per_node": 2,
            "data_volume_size": 200,
            "aws_spot_instance": True
        }
        errors = validate_sut_parameters(params, "aws")
        self.assertEqual([], errors)
    
    def test_valid_libvirt_parameters(self):
        """Test valid libvirt parameters"""
        params = {
            "cluster_size": 3,
            "libvirt_memory": 8,
            "libvirt_vcpus": 4,
            "data_volumes_per_node": 2
        }
        errors = validate_sut_parameters(params, "libvirt")
        self.assertEqual([], errors)
    
    def test_invalid_parameter_type(self):
        """Test invalid parameter type"""
        params = {
            "cluster_size": "not_an_int"  # Should be int
        }
        errors = validate_sut_parameters(params, "aws")
        self.assertGreater(len(errors), 0)
        self.assertIn("must be an integer", errors[0].lower())
    
    def test_invalid_parameter_for_provider(self):
        """Test parameter not supported by provider"""
        params = {
            "libvirt_memory": 8  # Not valid for AWS
        }
        errors = validate_sut_parameters(params, "aws")
        self.assertGreater(len(errors), 0)
        self.assertIn("not supported for provider", errors[0].lower())
    
    def test_unknown_parameter(self):
        """Test unknown parameter"""
        params = {
            "unknown_param": "value"
        }
        errors = validate_sut_parameters(params, "aws")
        self.assertGreater(len(errors), 0)
        self.assertIn("unknown parameter", errors[0].lower())


if __name__ == '__main__':
    unittest.main()
