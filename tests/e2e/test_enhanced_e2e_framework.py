#!/usr/bin/env python3
"""
Unit tests for Enhanced E2E Test Framework

Tests integration of SSH validation and emergency response capabilities
with the main E2E framework without requiring actual cloud resources.
"""

import unittest
import tempfile
import json
import getpass
import uuid
from pathlib import Path
from unittest.mock import patch, MagicMock
from enhanced_e2e_framework import EnhancedE2ETestFramework


class TestEnhancedE2ETestFramework(unittest.TestCase):
    """Test cases for Enhanced E2E Test Framework."""
    
    def setUp(self):
        """Set up test environment."""
        # Create user-specific temp directory
        username = getpass.getuser()
        test_id = str(uuid.uuid4())[:8]
        self.temp_dir = Path(tempfile.mkdtemp(prefix=f"exasol_test_{username}_{test_id}_"))
        
        # Create test configuration
        self.config = {
            'test_suites': {
                'test_suite': {
                    'provider': 'aws',
                    'parameters': {
                        'cluster_size': [1],
                        'instance_type': ['t3a.large'],
                        'data_volume_size': [100]
                    },
                    'combinations': '1-wise'
                }
            }
        }
        
        self.config_file = self.temp_dir / 'test_config.json'
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f)
        
        self.results_dir = self.temp_dir / 'results'
        self.results_dir.mkdir()
        
        self.framework = EnhancedE2ETestFramework(
            str(self.config_file),
            self.results_dir,
            dry_run=True,
            timeout_minutes=5
        )
    
    def tearDown(self):
        """Clean up test environment."""
        import shutil
        shutil.rmtree(self.temp_dir)
    
    def test_framework_initialization(self):
        """Test enhanced framework initialization."""
        self.assertTrue(self.framework.dry_run)
        self.assertEqual(self.framework.timeout_minutes, 5)
        self.assertIsNone(self.framework.ssh_validator)
        self.assertIsNone(self.framework.emergency_handler)
        self.assertIsNone(self.framework.resource_tracker)
    
    def test_setup_enhanced_components_dry_run(self):
        """Test setting up enhanced components in dry-run mode."""
        deploy_dir = self.temp_dir / 'test-deployment'
        deploy_dir.mkdir()
        
        self.framework._setup_enhanced_components(deploy_dir)
        
        self.assertIsNotNone(self.framework.ssh_validator)
        self.assertIsNotNone(self.framework.emergency_handler)
        self.assertIsNotNone(self.framework.resource_tracker)
        
        self.assertTrue(self.framework.ssh_validator.dry_run)
        self.assertTrue(self.framework.emergency_handler.dry_run)
        self.assertTrue(self.framework.resource_tracker.dry_run)
    
    def test_emergency_cleanup_callback(self):
        """Test emergency cleanup callback."""
        deployment_id = 'test-deployment'
        
        # Trigger callback
        self.framework._emergency_cleanup_callback(deployment_id)
        
        # Check that emergency result was recorded
        self.assertEqual(len(self.framework.enhanced_results), 1)
        result = self.framework.enhanced_results[0]
        
        self.assertEqual(result['deployment_id'], deployment_id)
        self.assertEqual(result['event_type'], 'emergency_cleanup')
        self.assertEqual(result['trigger'], 'timeout')
        self.assertTrue(result['dry_run'])
    
    def test_summarize_validation_results(self):
        """Test summarizing SSH validation results."""
        # Create mock validation results
        mock_results = [
            MagicMock(success=True, description="Test 1"),
            MagicMock(success=False, description="Test 2"),
            MagicMock(success=True, description="Test 3")
        ]
        
        # Convert to dict-like objects for asdict compatibility
        class MockResult:
            def __init__(self, success, description):
                self.success = success
                self.description = description
        
        mock_results = [
            MockResult(True, "Test 1"),
            MockResult(False, "Test 2"),
            MockResult(True, "Test 3")
        ]
        
        # Test with empty results first to avoid asdict issues
        summary = self.framework._summarize_validation_results([])
        self.assertEqual(summary['total_checks'], 0)
        
        # Test with actual SSH validation results (create real SSHValidationResult objects)
        from ssh_validator import SSHValidationResult
        
        mock_results = [
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
            ),
            SSHValidationResult(
                command="test3",
                description="Test 3",
                success=True,
                dry_run=True
            )
        ]
        
        summary = self.framework._summarize_validation_results(mock_results)
        self.assertEqual(summary['total_checks'], 3)
        self.assertEqual(summary['passed_checks'], 2)
        self.assertEqual(summary['failed_checks'], 1)
        self.assertAlmostEqual(summary['success_rate'], 2/3, places=2)
        self.assertTrue(summary['dry_run'])
        
        self.assertEqual(summary['total_checks'], 3)
        self.assertEqual(summary['passed_checks'], 2)
        self.assertEqual(summary['failed_checks'], 1)
        self.assertAlmostEqual(summary['success_rate'], 2/3, places=2)
        self.assertTrue(summary['dry_run'])
    
    def test_summarize_empty_validation_results(self):
        """Test summarizing empty validation results."""
        summary = self.framework._summarize_validation_results([])
        
        self.assertEqual(summary['total_checks'], 0)
        self.assertEqual(summary['passed_checks'], 0)
        self.assertEqual(summary['failed_checks'], 0)
        self.assertEqual(summary['success_rate'], 0)
        self.assertTrue(summary['dry_run'])
    
    def test_generate_enhanced_execution_plan(self):
        """Test enhanced execution plan generation."""
        test_plan = self.framework.generate_test_plan(dry_run=True)
        enhanced_plan = self.framework.generate_enhanced_execution_plan(test_plan)
        
        self.assertIn('test_plan', enhanced_plan)
        self.assertIn('enhanced_features', enhanced_plan)
        self.assertIn('ssh_validation_plans', enhanced_plan)
        self.assertIn('emergency_response_plans', enhanced_plan)
        
        # Check enhanced features
        features = enhanced_plan['enhanced_features']
        self.assertTrue(features['ssh_validation'])
        self.assertTrue(features['emergency_response'])
        self.assertTrue(features['resource_tracking'])
        self.assertTrue(features['timeout_monitoring'])
        
        # Check that plans are generated for each test
        self.assertEqual(len(enhanced_plan['ssh_validation_plans']), len(test_plan))
        self.assertEqual(len(enhanced_plan['emergency_response_plans']), len(test_plan))
    
    def test_save_enhanced_execution_plan(self):
        """Test saving enhanced execution plan."""
        test_plan = self.framework.generate_test_plan(dry_run=True)
        output_file = self.temp_dir / 'enhanced_plan.json'
        
        self.framework.save_enhanced_execution_plan(test_plan, output_file)
        
        self.assertTrue(output_file.exists())
        
        # Load and verify saved plan
        with open(output_file, 'r') as f:
            saved_plan = json.load(f)
        
        self.assertIn('test_plan', saved_plan)
        self.assertIn('enhanced_features', saved_plan)
        self.assertIn('ssh_validation_plans', saved_plan)
        self.assertIn('emergency_response_plans', saved_plan)
    
    def test_get_enhanced_results_summary_empty(self):
        """Test enhanced results summary when no results exist."""
        summary = self.framework.get_enhanced_results_summary()
        
        self.assertEqual(summary['status'], 'no_results')
        self.assertIn('No enhanced tests executed yet', summary['message'])
        self.assertTrue(summary['dry_run'])
    
    def test_get_enhanced_results_summary_with_results(self):
        """Test enhanced results summary with results."""
        # Add mock enhanced results
        self.framework.enhanced_results = [
            {
                'deployment_id': 'test-1',
                'event_type': 'test_event',
                'timestamp': 1234567890,
                'dry_run': True
            },
            {
                'deployment_id': 'test-2',
                'event_type': 'emergency_cleanup',
                'timestamp': 1234567891,
                'trigger': 'timeout',
                'dry_run': True
            }
        ]
        
        summary = self.framework.get_enhanced_results_summary()
        
        self.assertEqual(summary['total_enhanced_results'], 2)
        self.assertEqual(summary['emergency_events'], 1)
        self.assertTrue(summary['dry_run'])
        self.assertEqual(len(summary['enhanced_results']), 2)
    
    @patch('enhanced_e2e_framework.E2ETestFramework._run_single_test')
    def test_run_single_test_enhanced(self, mock_parent_run):
        """Test running single test with enhanced validation."""
        # Mock parent result
        mock_parent_result = {
            'deployment_id': 'test-123',
            'success': True,
            'duration': 60.0
        }
        mock_parent_run.return_value = mock_parent_result
        
        test_case = {
            'deployment_id': 'test-123',
            'provider': 'aws',
            'parameters': {'cluster_size': 1}
        }
        
        result = self.framework._run_single_test(test_case)
        
        # Check that enhanced validation was added
        self.assertIn('enhanced_validation', result)
        self.assertIn('emergency_response', result)
        
        # Check enhanced validation structure
        enhanced_val = result['enhanced_validation']
        self.assertIn('ssh_validation_performed', enhanced_val)
        self.assertIn('overall_success', enhanced_val)
        self.assertTrue(enhanced_val['dry_run'])
        
        # Check emergency response structure
        emergency_resp = result['emergency_response']
        self.assertIn('timeout_monitoring_active', emergency_resp)
        self.assertIn('resources_tracked', emergency_resp)
        self.assertTrue(emergency_resp['dry_run'])
    
    def test_perform_enhanced_validation_dry_run(self):
        """Test enhanced validation in dry-run mode."""
        deploy_dir = self.temp_dir / 'test-deployment'
        deploy_dir.mkdir()
        
        self.framework._setup_enhanced_components(deploy_dir)
        
        test_case = {
            'deployment_id': 'test-123',
            'parameters': {'data_volume_size': 100}
        }
        
        enhanced_val = self.framework._perform_enhanced_validation(deploy_dir, test_case)
        
        self.assertTrue(enhanced_val['ssh_validation_performed'])
        self.assertIn('symlink_validation', enhanced_val)
        self.assertIn('volume_validation', enhanced_val)
        self.assertIn('service_validation', enhanced_val)
        self.assertIn('database_validation', enhanced_val)
        self.assertIn('connectivity_validation', enhanced_val)
        self.assertIn('system_resources_validation', enhanced_val)
        self.assertTrue(enhanced_val['dry_run'])
    
    def test_get_emergency_response_info(self):
        """Test getting emergency response information."""
        deploy_dir = self.temp_dir / 'test-deployment'
        deploy_dir.mkdir()
        
        self.framework._setup_enhanced_components(deploy_dir)
        
        emergency_info = self.framework._get_emergency_response_info('test-deployment')
        
        self.assertIn('timeout_monitoring_active', emergency_info)
        self.assertIn('emergency_cleanup_performed', emergency_info)
        self.assertIn('resources_tracked', emergency_info)
        self.assertIn('estimated_cost', emergency_info)
        self.assertTrue(emergency_info['dry_run'])


class TestEnhancedE2EFrameworkMain(unittest.TestCase):
    """Test cases for enhanced framework main function."""
    
    def setUp(self):
        """Set up test environment."""
        # Create user-specific temp directory
        username = getpass.getuser()
        test_id = str(uuid.uuid4())[:8]
        self.temp_dir = Path(tempfile.mkdtemp(prefix=f"exasol_test_{username}_{test_id}_"))
        
        # Create test configuration
        self.config = {
            'test_suites': {
                'test_suite': {
                    'provider': 'aws',
                    'parameters': {
                        'cluster_size': [1]
                    },
                    'combinations': '1-wise'
                }
            }
        }
        
        self.config_file = self.temp_dir / 'test_config.json'
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f)
    
    def tearDown(self):
        """Clean up test environment."""
        import shutil
        shutil.rmtree(self.temp_dir)
    
    @patch('sys.argv', ['enhanced_e2e_framework.py', 'plan', '--config', 'test.json'])
    @patch('enhanced_e2e_framework.EnhancedE2ETestFramework')
    def test_main_plan_action(self, mock_framework_class):
        """Test main function with plan action."""
        mock_framework = MagicMock()
        mock_framework_class.return_value = mock_framework
        
        # Mock test plan generation
        mock_framework.generate_test_plan.return_value = [
            {'deployment_id': 'test-1', 'parameters': {}}
        ]
        
        # Import and run main
        from enhanced_e2e_framework import main
        
        # This would normally print and exit, but we'll just test the setup
        try:
            main()
        except SystemExit:
            pass  # Expected for CLI tool
        
        # Verify framework was created with correct parameters
        mock_framework_class.assert_called_once()
        
        # Verify plan generation was called
        mock_framework.generate_test_plan.assert_called_once_with(dry_run=True)


if __name__ == '__main__':
    unittest.main()