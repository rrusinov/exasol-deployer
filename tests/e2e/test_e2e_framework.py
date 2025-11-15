import unittest
import tempfile
import json
import os
import shutil
import sys
import getpass
import uuid
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

from e2e_framework import E2ETestFramework, ResourceQuotaMonitor, NotificationManager, HTMLReportGenerator


class TestE2EFramework(unittest.TestCase):

    def setUp(self):
        # Create user-specific temp directory
        username = getpass.getuser()
        test_id = str(uuid.uuid4())[:8]
        self.temp_dir = tempfile.mkdtemp(prefix=f"exasol_test_{username}_{test_id}_")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp_dir)

    def _create_config_file(self, config_dict):
        config_file = os.path.join(self.temp_dir, 'test_config.json')
        with open(config_file, 'w') as f:
            json.dump(config_dict, f)
        return config_file

    def test_2_wise_combinations(self):
        """Test 2-wise combination generation for 5 parameters with 2 values each."""
        config = {
            'test_suites': {
                'test_suite': {
                    'provider': 'aws',
                    'combinations': '2-wise',
                    'parameters': {
                        'param1': [1, 2],
                        'param2': [3, 4],
                        'param3': [5, 6],
                        'param4': [7, 8],
                        'param5': [9, 10]
                    }
                }
            }
        }
        config_file = self._create_config_file(config)
        with E2ETestFramework(config_file, Path(self.temp_dir)) as framework:
            plan = framework.generate_test_plan(dry_run=True)
        
        # Should generate 8 test cases
        self.assertEqual(len(plan), 8)
        
        # Each test should have test_type '2-wise'
        for test in plan:
            self.assertEqual(test['test_type'], '2-wise')
            self.assertIn('parameters', test)
            # Check that all expected parameters are present (framework may add additional ones like enable_spot_instances)
            expected_params = {'param1', 'param2', 'param3', 'param4', 'param5'}
            actual_params = set(test['parameters'].keys())
            self.assertTrue(expected_params.issubset(actual_params), 
                          f"Missing expected parameters. Expected at least {expected_params}, got {actual_params}")

    def test_1_wise_combinations(self):
        """Test 1-wise combination generation for 5 parameters with 2 values each."""
        config = {
            'test_suites': {
                'test_suite': {
                    'provider': 'aws',
                    'combinations': '1-wise',
                    'parameters': {
                        'param1': [1, 2],
                        'param2': [3, 4],
                        'param3': [5, 6],
                        'param4': [7, 8],
                        'param5': [9, 10]
                    }
                }
            }
        }
        config_file = self._create_config_file(config)
        with E2ETestFramework(config_file, Path(self.temp_dir)) as framework:
            plan = framework.generate_test_plan(dry_run=True)
            
            # Should generate 2 test cases
            self.assertEqual(len(plan), 2)
            
            # Each test should have test_type '1-wise'
            for test in plan:
                self.assertEqual(test['test_type'], '1-wise')
                self.assertIn('parameters', test)
                # Check that all expected parameters are present
                expected_params = {'param1', 'param2', 'param3', 'param4', 'param5'}
                actual_params = set(test['parameters'].keys())
                self.assertTrue(expected_params.issubset(actual_params), 
                              f"Missing expected parameters. Expected at least {expected_params}, got {actual_params}")

    def test_full_combinations(self):
        """Test full combination generation for 2 parameters with 2 values each."""
        config = {
            'test_suites': {
                'test_suite': {
                    'provider': 'aws',
                    'combinations': 'full',
                    'parameters': {
                        'param1': [1, 2],
                        'param2': [3, 4]
                    }
                }
            }
        }
        config_file = self._create_config_file(config)
        with E2ETestFramework(config_file, Path(self.temp_dir)) as framework:
            plan = framework.generate_test_plan(dry_run=True)
            
            # Should generate 4 test cases (2x2)
            self.assertEqual(len(plan), 4)
            
            # Each test should have test_type 'full'
            for test in plan:
                self.assertEqual(test['test_type'], 'full')
                self.assertIn('parameters', test)
                # Check that all expected parameters are present (framework may add additional ones)
                expected_params = {'param1', 'param2'}
                actual_params = set(test['parameters'].keys())
                self.assertTrue(expected_params.issubset(actual_params), 
                              f"Missing expected parameters. Expected at least {expected_params}, got {actual_params}")

    def test_default_combinations(self):
        """Test default 1-wise combinations when combinations not specified."""
        config = {
            'test_suites': {
                'test_suite': {
                    'provider': 'aws',
                    'parameters': {
                        'param1': [1, 2],
                        'param2': [3, 4]
                    }
                }
            }
        }
        config_file = self._create_config_file(config)
        with E2ETestFramework(config_file, Path(self.temp_dir)) as framework:
            plan = framework.generate_test_plan(dry_run=True)
            
            # Should generate 2 test cases (1-wise by default)
            self.assertEqual(len(plan), 2)
            
            # Each test should have test_type '1-wise'
            for test in plan:
                self.assertEqual(test['test_type'], '1-wise')
                # Check that all expected parameters are present
                expected_params = {'param1', 'param2'}
                actual_params = set(test['parameters'].keys())
                self.assertTrue(expected_params.issubset(actual_params), 
                              f"Missing expected parameters. Expected at least {expected_params}, got {actual_params}")

    def test_1_wise_with_different_value_counts(self):
        """Test 1-wise with parameters having different numbers of values."""
        config = {
            'test_suites': {
                'test_suite': {
                    'provider': 'aws',
                    'combinations': '1-wise',
                    'parameters': {
                        'param1': [1, 2],      # 2 values
                        'param2': [3, 4, 5],   # 3 values
                        'param3': [6]          # 1 value
                    }
                }
            }
        }
        config_file = self._create_config_file(config)
        with E2ETestFramework(config_file, Path(self.temp_dir)) as framework:
            plan = framework.generate_test_plan(dry_run=True)
            
            # Should generate 3 test cases (max values)
            self.assertEqual(len(plan), 3)
            
            # Check parameter values in combinations
            params_list = [test['parameters'] for test in plan]
            
            # First test: all first values
            self.assertEqual(params_list[0]['param1'], 1)
            self.assertEqual(params_list[0]['param2'], 3)
            self.assertEqual(params_list[0]['param3'], 6)
            
            # Second test: all second values (param3 repeats first)
            self.assertEqual(params_list[1]['param1'], 2)
            self.assertEqual(params_list[1]['param2'], 4)
            self.assertEqual(params_list[1]['param3'], 6)
            
            # Third test: param1 uses second value (cycle), param2 third value
            self.assertEqual(params_list[2]['param1'], 2)  # cycles to second
            self.assertEqual(params_list[2]['param2'], 5)
            self.assertEqual(params_list[2]['param3'], 6)


class TestE2EFrameworkUtilities(unittest.TestCase):

    def test_resource_quota_monitor_enforces_limits(self):
        monitor = ResourceQuotaMonitor({
            'max_cluster_size_per_test': 2,
            'max_total_instances': 2,
            'max_parallel_executions': 1
        })
        violating_plan = [{'parameters': {'cluster_size': 3}}]
        with self.assertRaises(ValueError):
            monitor.evaluate_plan(violating_plan, max_parallel=1)

        valid_plan = [{'parameters': {
            'cluster_size': 2,
            'data_volumes_per_node': 1,
            'data_volume_size': 50,
            'instance_type': 'm6idn.large'
        }}]
        metrics = monitor.evaluate_plan(valid_plan, max_parallel=1)
        self.assertEqual(metrics['total_instances'], 2)
        self.assertEqual(metrics['max_cluster_size'], 2)

    def test_notification_manager_flushes_events(self):
        # Create user-specific temp directory
        username = getpass.getuser()
        test_id = str(uuid.uuid4())[:8]
        temp_dir = Path(tempfile.mkdtemp(prefix=f"exasol_test_{username}_{test_id}_"))
        self.addCleanup(shutil.rmtree, temp_dir)
        manager = NotificationManager(temp_dir, {
            'enabled': True,
            'slow_test_threshold_seconds': 1,
            'notify_on_slow_tests': True
        })
        manager.record_result({'deployment_id': 'test', 'success': False, 'duration': 5, 'error': 'boom'})
        summary = manager.flush_to_disk()
        if summary is None:
            self.fail("Expected notification summary to be emitted")
        self.assertTrue(Path(summary['file']).exists())
        self.assertEqual(summary['event_count'], 1)

    def test_html_report_generator_produces_files(self):
        # Create user-specific temp directory
        username = getpass.getuser()
        test_id = str(uuid.uuid4())[:8]
        temp_dir = Path(tempfile.mkdtemp(prefix=f"exasol_test_{username}_{test_id}_"))
        self.addCleanup(shutil.rmtree, temp_dir)
        generator = HTMLReportGenerator(temp_dir)
        summary = {
            'total_tests': 1,
            'passed': 1,
            'failed': 0,
            'results': [
                {
                    'deployment_id': 'demo',
                    'provider': 'aws',
                    'test_type': '1-wise',
                    'duration': 12.5,
                    'success': True,
                    'error': None
                }
            ]
        }
        generator.generate(summary, 'report.html')
        self.assertTrue((temp_dir / 'report.html').exists())
        self.assertTrue((temp_dir / 'latest_results.html').exists())


if __name__ == '__main__':
    unittest.main()
