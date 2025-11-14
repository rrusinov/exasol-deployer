#!/usr/bin/env python3
"""
Exasol E2E Test Framework

A comprehensive end-to-end testing framework for Exasol deployments that can:
- Define test parameters via JSON/YAML configurations
- Generate test plans from parameter combinations
- Execute tests in parallel across cloud providers
- Validate deployment outcomes
- Manage cleanup and resource lifecycle
"""

import argparse
import concurrent.futures
import json
import logging
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional


class E2ETestFramework:
    """Main E2E test framework class."""

    def __init__(self, config_path: str, results_dir: Optional[Path] = None):
        self.config_path = Path(config_path)
        self.work_dir = Path(tempfile.mkdtemp(prefix="exasol_e2e_"))
        self.results_dir = results_dir if results_dir else Path('./tmp/e2e-results/')
        self.results_dir.mkdir(parents=True, exist_ok=True)
        self.results = []

        # Setup logging
        self._setup_logging()
        self.config = self._load_config()

    def _setup_logging(self):
        """Setup logging configuration."""
        log_file = self.results_dir / f"e2e_test_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)

    def _load_config(self) -> Dict[str, Any]:
        """Load test configuration from JSON/YAML file."""
        if not self.config_path.exists():
            raise FileNotFoundError(f"Configuration file not found: {self.config_path}")

        with open(self.config_path, 'r', encoding='utf-8') as f:
            if self.config_path.suffix.lower() in ['.json']:
                config = json.load(f)
            else:
                # For now, assume JSON; could extend to YAML later
                config = json.load(f)

        # Validate for misspelled keys
        self._validate_config_keys(config)
        return config

    def _validate_config_keys(self, config: Dict[str, Any]):
        """Validate configuration for misspelled keys."""
        valid_keys = {
            'test_suites',
            'provider',
            'parameters',
            'combinations',
            'cluster_size',
            'instance_type',
            'data_volumes_per_node',
            'data_volume_size',
            'root_volume_size'
        }

        common_typos = {
            'clustor_size': 'cluster_size',
            'instnce_type': 'instance_type',
            'data_volums_per_node': 'data_volumes_per_node',
            'data_volum_size': 'data_volume_size',
            'root_volum_size': 'root_volume_size',
            'variaton_tests': 'variation_tests',
            'variaton': 'variation',
            'base_paramters': 'base_parameters',
            'paramters': 'parameters'
        }

        def check_keys(obj, path=""):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    current_path = f"{path}.{key}" if path else key
                    if key in common_typos:
                        raise ValueError(f"Possible misspelling in config at {current_path}: '{key}' should be '{common_typos[key]}'")
                    # Skip validation for suite names and parameter names
                    if not (path == 'test_suites' or 'parameters' in path):
                        if key not in valid_keys:
                            self.logger.warning(f"Unknown key in config at {current_path}: '{key}'")
                    check_keys(value, current_path)
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    check_keys(item, f"{path}[{i}]")

        check_keys(config)

    def generate_test_plan(self, dry_run: bool = False) -> List[Dict[str, Any]]:
        """Generate test plan from configuration parameters."""
        test_plan = []

        for suite_name, suite_config in self.config.get('test_suites', {}).items():
            combinations_type = suite_config.get('combinations', 'full')
            if combinations_type == '2-wise':
                combinations = self._generate_2_wise_combinations(suite_config)
            elif combinations_type == '1-wise':
                combinations = self._generate_1_wise_combinations(suite_config)
            else:
                combinations = self._generate_full_combinations(suite_config)

            for combo in combinations:
                test_case = {
                    'suite': suite_name,
                    'provider': suite_config['provider'],
                    'test_type': combinations_type,
                    'parameters': combo,
                    'deployment_id': f"{suite_name}_{hash(str(combo)) % 10000:04d}"
                }
                test_plan.append(test_case)

        if dry_run:
            print(f"Dry run: Generated {len(test_plan)} test cases")
            for i, test in enumerate(test_plan):
                print(f"  {i+1}: {test['deployment_id']} - {test['parameters']}")
        
        return test_plan

    def _generate_2_wise_combinations(self, suite_config: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Generate 2-wise parameter combinations for a test suite."""
        parameters = suite_config.get('parameters', {})
        param_names = list(parameters.keys())
        param_values = [parameters[name] if isinstance(parameters[name], list) else [parameters[name]] for name in param_names]

        # For this implementation, use a simple pairwise covering for up to 5 parameters
        # Using a covering design for 5 parameters with 2 values each
        if len(param_names) == 5 and all(len(v) == 2 for v in param_values):
            # Covering matrix: each row is a combination, 1=first value, 2=second value
            covering_matrix = [
                [1, 1, 1, 1, 1],
                [1, 1, 2, 2, 2],
                [1, 2, 1, 2, 1],
                [1, 2, 2, 1, 2],
                [2, 1, 1, 2, 2],
                [2, 1, 2, 1, 1],
                [2, 2, 1, 1, 2],
                [2, 2, 2, 2, 1],
            ]
            combinations = []
            for row in covering_matrix:
                combo = {}
                for i, idx in enumerate(row):
                    combo[param_names[i]] = param_values[i][idx - 1]
                combinations.append(combo)
            return combinations
        else:
            # For other cases, fall back to full combinations
            return self._generate_full_combinations(suite_config)

    def _generate_1_wise_combinations(self, suite_config: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Generate 1-wise parameter combinations for a test suite."""
        parameters = suite_config.get('parameters', {})
        param_names = list(parameters.keys())
        param_values = [parameters[name] if isinstance(parameters[name], list) else [parameters[name]] for name in param_names]

        # 1-wise: ensure every parameter value appears at least once
        # Minimal number of tests is the maximum number of values across parameters
        max_vals = max(len(v) for v in param_values) if param_values else 0
        combinations = []
        for i in range(max_vals):
            combo = {}
            for name, vals in zip(param_names, param_values):
                # Use the i-th value if available, otherwise use the first
                combo[name] = vals[min(i, len(vals) - 1)]
            combinations.append(combo)
        return combinations

    def _generate_full_combinations(self, suite_config: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Generate full Cartesian product of parameter combinations."""
        parameters = suite_config.get('parameters', {})
        param_names = list(parameters.keys())
        param_values = [parameters[name] if isinstance(parameters[name], list) else [parameters[name]] for name in param_names]

        combinations = [{}]
        for param_name, param_vals in zip(param_names, param_values):
            new_combinations = []
            for combo in combinations:
                for value in param_vals:
                    new_combo = combo.copy()
                    new_combo[param_name] = value
                    new_combinations.append(new_combo)
            combinations = new_combinations
        return combinations

    def run_tests(self, test_plan: List[Dict[str, Any]], max_parallel: int = 1) -> List[Dict[str, Any]]:
        """Execute tests in parallel."""
        results = []
        start_time = time.time()

        self.logger.info(f"Starting test execution with {len(test_plan)} tests, max_parallel={max_parallel}")

        with concurrent.futures.ThreadPoolExecutor(max_workers=max_parallel) as executor:
            futures = [executor.submit(self._run_single_test, test) for test in test_plan]

            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                results.append(result)
                status = 'PASS' if result['success'] else 'FAIL'
                self.logger.info(f"Completed: {result['deployment_id']} - {status} ({result['duration']:.1f}s)")

        total_time = time.time() - start_time
        self._save_results(results, total_time)
        self._print_summary(results, total_time)

        return results





    def _save_results(self, results: List[Dict[str, Any]], total_time: float):
        """Save test results to JSON file."""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        results_file = self.results_dir / f"test_results_{timestamp}.json"

        summary = {
            'timestamp': timestamp,
            'total_tests': len(results),
            'passed': sum(1 for r in results if r['success']),
            'failed': sum(1 for r in results if not r['success']),
            'total_time': total_time,
            'results': results
        }

        with open(results_file, 'w', encoding='utf-8') as f:
            json.dump(summary, f, indent=2, default=str)

        self.logger.info(f"Results saved to {results_file}")

    def _print_summary(self, results: List[Dict[str, Any]], total_time: float):
        """Print test execution summary."""
        passed = sum(1 for r in results if r['success'])
        failed = len(results) - passed

        print(f"\n{'='*50}")
        print("E2E TEST SUMMARY")
        print(f"{'='*50}")
        print(f"Total Tests: {len(results)}")
        print(f"Passed: {passed}")
        print(f"Failed: {failed}")
        print(f"Success Rate: {passed/len(results)*100:.1f}%" if results else "Success Rate: N/A")
        print(f"Total Time: {total_time:.1f}s")
        print(f"Average Time: {total_time/len(results):.1f}s per test" if results else "Average Time: N/A")

        if failed > 0:
            print(f"\n{'='*50}")
            print("FAILED TESTS:")
            print(f"{'='*50}")
            for result in results:
                if not result['success']:
                    print(f"- {result['deployment_id']}: {result.get('error', 'Unknown error')}")

    def _run_single_test(self, test_case: Dict[str, Any]) -> Dict[str, Any]:
        """Run a single test case."""
        deployment_id = test_case['deployment_id']
        provider = test_case['provider']
        test_type = test_case.get('test_type', 'matrix')

        result = {
            'deployment_id': deployment_id,
            'suite': test_case['suite'],
            'test_type': test_type,
            'success': False,
            'duration': 0,
            'error': None,
            'logs': [],
            'variation_results': []
        }

        start_time = time.time()

        # Create deployment directory
        deploy_dir = self.work_dir / deployment_id
        deploy_dir.mkdir(exist_ok=True)

        try:
            if test_type in ['2-wise', '1-wise', 'full']:
                # Run test
                params = test_case['parameters']
                result['parameters'] = params

                # Initialize deployment
                self._init_deployment(deploy_dir, provider, params)

                # Deploy
                self._deploy(deploy_dir, params)

                # Validate
                validation_result = self._validate_deployment(deploy_dir, params)
                result['validation'] = validation_result
                result['success'] = validation_result['success']
            else:
                raise ValueError(f"Unsupported test_type: {test_type}")

        except Exception as e:
            result['error'] = str(e)
            result['logs'].append(f"Error: {e}")

        finally:
            result['duration'] = time.time() - start_time

            # Cleanup
            try:
                self._cleanup_deployment(deploy_dir)
            except Exception as e:
                result['logs'].append(f"Cleanup error: {e}")

        return result

    def _init_deployment(self, deploy_dir: Path, provider: str, params: Dict[str, Any]):
        """Initialize deployment using exasol CLI."""
        cmd = [
            './exasol', 'init',
            '--provider', provider,
            '--deployment-dir', str(deploy_dir)
        ]

        # Add parameters as needed
        if 'cluster_size' in params:
            cmd.extend(['--cluster-size', str(params['cluster_size'])])
        if 'instance_type' in params:
            cmd.extend(['--instance-type', params['instance_type']])

        result = subprocess.run(cmd, capture_output=True, text=True, cwd=self.work_dir.parent.parent)
        if result.returncode != 0:
            raise RuntimeError(f"Init failed: {result.stderr}")

    def _deploy(self, deploy_dir: Path, params: Dict[str, Any]):
        """Deploy using exasol CLI."""
        cmd = ['./exasol', 'deploy', '--deployment-dir', str(deploy_dir)]

        result = subprocess.run(cmd, capture_output=True, text=True, cwd=self.work_dir.parent.parent)
        if result.returncode != 0:
            raise RuntimeError(f"Deploy failed: {result.stderr}")

    def _validate_deployment(self, deploy_dir: Path, params: Dict[str, Any]) -> Dict[str, Any]:
        """Validate deployment outcomes."""
        validation = {
            'success': True,
            'checks': []
        }

        # Check if terraform state exists
        state_file = deploy_dir / '.terraform' / 'terraform.tfstate'
        if state_file.exists():
            validation['checks'].append({'check': 'terraform_state_exists', 'status': 'pass'})
        else:
            validation['checks'].append({'check': 'terraform_state_exists', 'status': 'fail'})
            validation['success'] = False

        # Check terraform outputs
        outputs_file = deploy_dir / 'outputs.tf'
        if outputs_file.exists():
            validation['checks'].append({'check': 'outputs_file_exists', 'status': 'pass'})
        else:
            validation['checks'].append({'check': 'outputs_file_exists', 'status': 'fail'})
            validation['success'] = False

        # Check inventory file (generated by terraform)
        inventory_file = deploy_dir / 'inventory.ini'
        if inventory_file.exists():
            validation['checks'].append({'check': 'inventory_file_exists', 'status': 'pass'})

            # Validate cluster size in inventory if specified
            if 'cluster_size' in params:
                try:
                    with open(inventory_file, 'r', encoding='utf-8') as f:
                        content = f.read()
                        # Count exasol-data nodes (rough estimate)
                        node_count = content.count('[exasol-data]')
                        if node_count == params['cluster_size']:
                            validation['checks'].append({
                                'check': 'cluster_size_matches',
                                'expected': params['cluster_size'],
                                'actual': node_count,
                                'status': 'pass'
                            })
                        else:
                            validation['checks'].append({
                                'check': 'cluster_size_matches',
                                'expected': params['cluster_size'],
                                'actual': node_count,
                                'status': 'fail'
                            })
                            validation['success'] = False
                except Exception as e:
                    validation['checks'].append({
                        'check': 'inventory_parsing',
                        'error': str(e),
                        'status': 'fail'
                    })
                    validation['success'] = False
        else:
            validation['checks'].append({'check': 'inventory_file_exists', 'status': 'fail'})
            validation['success'] = False

        # Check for terraform apply success by looking for error logs
        terraform_log = deploy_dir / 'terraform.log'
        if terraform_log.exists():
            try:
                with open(terraform_log, 'r', encoding='utf-8') as f:
                    log_content = f.read()
                    if 'Error:' in log_content or 'error' in log_content.lower():
                        validation['checks'].append({
                            'check': 'terraform_apply_success',
                            'status': 'fail',
                            'details': 'Errors found in terraform log'
                        })
                        validation['success'] = False
                    else:
                        validation['checks'].append({'check': 'terraform_apply_success', 'status': 'pass'})
            except Exception as e:
                validation['checks'].append({
                    'check': 'terraform_log_check',
                    'error': str(e),
                    'status': 'fail'
                })

        return validation

    def _cleanup_deployment(self, deploy_dir: Path):
        """Cleanup deployment resources."""
        if deploy_dir.exists():
            cmd = ['./exasol', 'destroy', '--deployment-dir', str(deploy_dir), '--force']

            result = subprocess.run(cmd, capture_output=True, text=True, cwd=self.work_dir.parent.parent)
            if result.returncode != 0:
                print(f"Warning: Cleanup failed for {deploy_dir}: {result.stderr}")

            # Remove directory
            import shutil
            shutil.rmtree(deploy_dir, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description='Exasol E2E Test Framework')
    parser.add_argument('action', choices=['plan', 'run'], help='Action to perform')
    parser.add_argument('--config', required=True, help='Path to test configuration file')
    parser.add_argument('--results-dir', default='tests/e2e/results', help='Path to results directory')
    parser.add_argument('--dry-run', action='store_true', help='Generate plan without executing')
    parser.add_argument('--parallel', type=int, default=1, help='Maximum parallel executions')
    parser.add_argument('--filter', help='Filter test combinations (not implemented yet)')

    args = parser.parse_args()

    framework = E2ETestFramework(args.config, Path(args.results_dir))

    if args.action == 'plan':
        framework.generate_test_plan(dry_run=True)
    elif args.action == 'run':
        test_plan = framework.generate_test_plan(dry_run=args.dry_run)
        if not args.dry_run:
            results = framework.run_tests(test_plan, max_parallel=args.parallel)

            # Print summary
            passed = sum(1 for r in results if r['success'])
            total = len(results)
            print(f"\nResults: {passed}/{total} tests passed")

            if passed < total:
                print("Failed tests:")
                for r in results:
                    if not r['success']:
                        print(f"  - {r['deployment_id']}: {r.get('error', 'Unknown error')}")


if __name__ == '__main__':
    main()