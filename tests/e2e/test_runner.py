#!/usr/bin/env python3
"""
Unit Test Runner with Temporary Directory Management

Provides a clean way to run unit tests with temporary directories that
are automatically cleaned up unless explicitly preserved.
"""

import argparse
import tempfile
import shutil
import sys
import subprocess
import os
from pathlib import Path
import atexit
import time


class TestRunner:
    """Enhanced test runner with temporary directory management."""
    
    def __init__(self, test_dir: Path, verbose: bool = False, keep_results: bool = False):
        self.test_dir = Path(test_dir)
        self.verbose = verbose
        self.keep_results = keep_results
        
        # Temporary directories management
        self.temp_dirs = []
        self.cleanup_dirs = []
        
        # Set up temporary results directory if not specified
        if not self.keep_results:
            self.temp_results_dir = Path(tempfile.mkdtemp(prefix="exasol_test_results_"))
            self.temp_dirs.append(self.temp_results_dir)
            self.cleanup_dirs.append(self.temp_results_dir)
            
            # Register cleanup
            atexit.register(self._cleanup_temp)
    
    def _cleanup_temp(self):
        """Clean up temporary directories."""
        for temp_dir in self.cleanup_dirs:
            try:
                shutil.rmtree(temp_dir, ignore_errors=True)
                if self.verbose:
                    print(f"Cleaned up temporary directory: {temp_dir}")
            except Exception as e:
                if self.verbose:
                    print(f"Warning: Failed to cleanup {temp_dir}: {e}")
    
    def run_test_module(self, module_name: str) -> dict:
        """Run a single test module and return results."""
        start_time = time.time()
        
        # Set up environment for temporary directory
        env = dict(os.environ)
        if hasattr(self, 'temp_results_dir'):
            env['TEST_RESULTS_DIR'] = str(self.temp_results_dir)
        
        try:
            # Run the test module
            cmd = [sys.executable, '-m', 'unittest', module_name, '-v']
            if self.verbose:
                print(f"Running: {' '.join(cmd)}")
            
            result = subprocess.run(
                cmd,
                cwd=self.test_dir,
                capture_output=not self.verbose,
                text=True,
                env=env,
                timeout=300  # 5 minute timeout
            )
            
            execution_time = time.time() - start_time
            
            return {
                'module': module_name,
                'success': result.returncode == 0,
                'execution_time': execution_time,
                'stdout': result.stdout if not self.verbose else None,
                'stderr': result.stderr if not self.verbose else None,
                'exit_code': result.returncode
            }
            
        except subprocess.TimeoutExpired:
            return {
                'module': module_name,
                'success': False,
                'execution_time': time.time() - start_time,
                'error': 'Test timed out after 5 minutes',
                'exit_code': -1
            }
        except Exception as e:
            return {
                'module': module_name,
                'success': False,
                'execution_time': time.time() - start_time,
                'error': str(e),
                'exit_code': -2
            }
    
    def run_all_tests(self) -> dict:
        """Run all test modules and return summary."""
        test_modules = [
            'test_ssh_validator',
            'test_emergency_handler', 
            'test_enhanced_e2e_framework'
        ]
        
        results = {
            'total_modules': len(test_modules),
            'passed': 0,
            'failed': 0,
            'total_time': 0,
            'modules': [],
            'temp_results_dir': str(getattr(self, 'temp_results_dir', 'None')),
            'cleanup_scheduled': not self.keep_results
        }
        
        print("🧪 Running Enhanced E2E Framework Unit Tests")
        print("=" * 50)
        
        for module in test_modules:
            if self.verbose:
                print(f"\nTesting {module}...")
            
            module_result = self.run_test_module(module)
            results['modules'].append(module_result)
            results['total_time'] += module_result['execution_time']
            
            if module_result['success']:
                results['passed'] += 1
                if not self.verbose:
                    print(f"✓ {module}")
            else:
                results['failed'] += 1
                if not self.verbose:
                    print(f"✗ {module}")
                    if module_result.get('error'):
                        print(f"  Error: {module_result['error']}")
        
        return results
    
    def print_summary(self, results: dict):
        """Print test results summary."""
        print(f"\n{'='*50}")
        print("UNIT TEST SUMMARY")
        print(f"{'='*50}")
        print(f"Total modules: {results['total_modules']}")
        print(f"Passed: {results['passed']}")
        print(f"Failed: {results['failed']}")
        print(f"Success rate: {results['passed']/results['total_modules']*100:.1f}%")
        print(f"Total time: {results['total_time']:.2f}s")
        
        if results['failed'] > 0:
            print(f"\n{'='*50}")
            print("FAILED MODULES:")
            print(f"{'='*50}")
            for module in results['modules']:
                if not module['success']:
                    print(f"- {module['module']}: {module.get('error', 'Exit code ' + str(module.get('exit_code', 'unknown')))}")
        
        # Show temporary directory info
        temp_dir = results['temp_results_dir']
        if temp_dir != 'None' and temp_dir != 'None':
            if not self.keep_results and results['cleanup_scheduled']:
                print(f"\n📁 Temporary results: {temp_dir}")
                print("🧹 Results will be automatically cleaned up.")
                print("💡 To preserve results, rerun with --keep-results")
                print(f"   Or specify: --test-results-dir {temp_dir}")
            elif self.keep_results:
                print(f"\n📁 Results preserved in: {temp_dir}")
        else:
            print(f"\n📁 No temporary directory created")
        
        # Show rerun command for failed tests
        if results['failed'] > 0:
            failed_modules = [m['module'] for m in results['modules'] if not m['success']]
            print(f"\n🔄 To rerun failed tests:")
            print(f"   python3 {' '.join(sys.argv)} --keep-results --verbose")
            if results['temp_results_dir'] != 'None':
                print(f"   --test-results-dir {results['temp_results_dir']}")


def main():
    """Main function for test runner."""
    parser = argparse.ArgumentParser(description='Enhanced E2E Framework Test Runner')
    parser.add_argument('--test-dir', default='.', help='Test directory (default: current)')
    parser.add_argument('--test-results-dir', help='Directory for test results (default: temporary)')
    parser.add_argument('--keep-results', action='store_true', help='Keep temporary results directory')
    parser.add_argument('--verbose', action='store_true', help='Show detailed test output')
    parser.add_argument('--module', help='Run specific test module only')
    
    args = parser.parse_args()
    
    # Initialize test runner
    runner = TestRunner(
        test_dir=Path(args.test_dir),
        verbose=args.verbose,
        keep_results=args.keep_results
    )
    
    # Override temp results directory if specified
    if args.test_results_dir:
        custom_results_dir = Path(args.test_results_dir)
        custom_results_dir.mkdir(parents=True, exist_ok=True)
        runner.temp_results_dir = custom_results_dir
        # Don't cleanup custom directory
        if runner.temp_results_dir in runner.cleanup_dirs:
            runner.cleanup_dirs.remove(runner.temp_results_dir)
    
    # Run tests
    if args.module:
        # Run single module
        result = runner.run_test_module(args.module)
        test_results = {
            'total_modules': 1,
            'passed': 1 if result['success'] else 0,
            'failed': 0 if result['success'] else 1,
            'total_time': result['execution_time'],
            'modules': [result],
            'temp_results_dir': str(getattr(runner, 'temp_results_dir', 'None')),
            'cleanup_scheduled': not args.keep_results
        }
        runner.print_summary(test_results)
        sys.exit(0 if result['success'] else 1)
    else:
        # Run all tests
        results = runner.run_all_tests()
        runner.print_summary(results)
        sys.exit(0 if results['passed'] == results['total_modules'] else 1)


if __name__ == '__main__':
    main()