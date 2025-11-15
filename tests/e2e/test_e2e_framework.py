import unittest
import tempfile
import json
import os
from pathlib import Path
from e2e_framework import E2ETestFramework


class TestE2EFramework(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

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
        framework = E2ETestFramework(config_file, Path(self.temp_dir))
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
        framework = E2ETestFramework(config_file, Path(self.temp_dir))
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
        framework = E2ETestFramework(config_file, Path(self.temp_dir))
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
        framework = E2ETestFramework(config_file, Path(self.temp_dir))
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
        framework = E2ETestFramework(config_file, Path(self.temp_dir))
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


if __name__ == '__main__':
    unittest.main()