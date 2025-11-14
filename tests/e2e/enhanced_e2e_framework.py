#!/usr/bin/env python3
"""
Enhanced E2E Test Framework with Live System Validation

Integrates SSH validation and emergency response capabilities into the main
E2E framework for comprehensive testing of Exasol deployments.
"""

import json
import logging
import time
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import asdict

from e2e_framework import E2ETestFramework
from ssh_validator import SSHValidator
from emergency_handler import EmergencyHandler, ResourceTracker


class EnhancedE2ETestFramework(E2ETestFramework):
    """Enhanced E2E framework with live system validation and emergency response."""
    
    def __init__(self, config_path: str, results_dir: Optional[Path] = None, 
                 dry_run: bool = True, timeout_minutes: int = 30):
        super().__init__(config_path, results_dir)
        
        self.dry_run = dry_run
        self.timeout_minutes = timeout_minutes
        
        # Enhanced validation components
        self.ssh_validator: Optional[SSHValidator] = None
        self.emergency_handler: Optional[EmergencyHandler] = None
        self.resource_tracker: Optional[ResourceTracker] = None
        
        # Enhanced results
        self.enhanced_results: List[Dict[str, Any]] = []
        
        self.logger.info(f"Enhanced E2E Framework initialized - Dry run: {self.dry_run}")
    
    def _setup_enhanced_components(self, deploy_dir: Path):
        """Set up SSH validator and emergency handler for deployment."""
        if not self.dry_run:
            # Initialize SSH validator for live system checks
            self.ssh_validator = SSHValidator(deploy_dir, dry_run=False)
            
            # Initialize emergency handler for timeout monitoring
            self.emergency_handler = EmergencyHandler(
                deploy_dir, 
                timeout_minutes=self.timeout_minutes, 
                dry_run=False
            )
            
            # Initialize resource tracker
            self.resource_tracker = ResourceTracker(deploy_dir, dry_run=False)
            
            # Add emergency cleanup callback
            self.emergency_handler.add_cleanup_callback(self._emergency_cleanup_callback)
        else:
            # Initialize components in dry-run mode
            self.ssh_validator = SSHValidator(deploy_dir, dry_run=True)
            self.emergency_handler = EmergencyHandler(deploy_dir, timeout_minutes=self.timeout_minutes, dry_run=True)
            self.resource_tracker = ResourceTracker(deploy_dir, dry_run=True)
    
    def _emergency_cleanup_callback(self, deployment_id: str):
        """Callback for emergency cleanup situations."""
        self.logger.error(f"Emergency cleanup triggered for deployment: {deployment_id}")
        
        # Log emergency cleanup event
        emergency_result = {
            'deployment_id': deployment_id,
            'event_type': 'emergency_cleanup',
            'timestamp': time.time(),
            'trigger': 'timeout',
            'dry_run': self.dry_run
        }
        
        self.enhanced_results.append(emergency_result)
    
    def _run_single_test(self, test_case: Dict[str, Any]) -> Dict[str, Any]:
        """Run a single test case with enhanced validation."""
        deployment_id = test_case['deployment_id']
        
        # Create deployment directory
        deploy_dir = self.work_dir / deployment_id
        deploy_dir.mkdir(exist_ok=True)
        
        # Set up enhanced components
        self._setup_enhanced_components(deploy_dir)
        
        # Get base result from parent class
        result = super()._run_single_test(test_case)
        
        # Add enhanced validation results
        result['enhanced_validation'] = self._perform_enhanced_validation(deploy_dir, test_case)
        result['emergency_response'] = self._get_emergency_response_info(deployment_id)
        
        return result
    
    def _perform_enhanced_validation(self, deploy_dir: Path, test_case: Dict[str, Any]) -> Dict[str, Any]:
        """Perform enhanced SSH-based validation."""
        enhanced_validation = {
            'ssh_validation_performed': False,
            'symlink_validation': {},
            'volume_validation': {},
            'service_validation': {},
            'database_validation': {},
            'connectivity_validation': {},
            'system_resources_validation': {},
            'overall_success': False,
            'dry_run': self.dry_run
        }
        
        try:
            if self.ssh_validator:
                enhanced_validation['ssh_validation_performed'] = True
                
                # Perform all SSH validations
                enhanced_validation['symlink_validation'] = self._summarize_validation_results(
                    self.ssh_validator.validate_symlinks()
                )
                
                # Validate volume sizes if specified
                params = test_case.get('parameters', {})
                if 'data_volume_size' in params:
                    enhanced_validation['volume_validation'] = self._summarize_validation_results(
                        self.ssh_validator.validate_volume_sizes(params['data_volume_size'])
                    )
                
                enhanced_validation['service_validation'] = self._summarize_validation_results(
                    self.ssh_validator.validate_services()
                )
                
                enhanced_validation['database_validation'] = self._summarize_validation_results(
                    self.ssh_validator.validate_database_installation()
                )
                
                enhanced_validation['connectivity_validation'] = self._summarize_validation_results(
                    self.ssh_validator.validate_cluster_connectivity()
                )
                
                enhanced_validation['system_resources_validation'] = self._summarize_validation_results(
                    self.ssh_validator.validate_system_resources()
                )
                
                # Calculate overall success
                all_validations = [
                    enhanced_validation['symlink_validation'],
                    enhanced_validation['volume_validation'],
                    enhanced_validation['service_validation'],
                    enhanced_validation['database_validation'],
                    enhanced_validation['connectivity_validation'],
                    enhanced_validation['system_resources_validation']
                ]
                
                # Filter out empty validations
                all_validations = [v for v in all_validations if v.get('total_checks', 0) > 0]
                
                if all_validations:
                    enhanced_validation['overall_success'] = all(
                        v.get('success_rate', 0) >= 0.8 for v in all_validations
                    )
                else:
                    enhanced_validation['overall_success'] = True  # No validations performed
            
        except Exception as e:
            enhanced_validation['error'] = str(e)
            self.logger.error(f"Enhanced validation failed: {e}")
        
        return enhanced_validation
    
    def _summarize_validation_results(self, results: List) -> Dict[str, Any]:
        """Summarize SSH validation results."""
        if not results:
            return {
                'total_checks': 0,
                'passed_checks': 0,
                'failed_checks': 0,
                'success_rate': 0,
                'dry_run': self.dry_run
            }
        
        total = len(results)
        passed = sum(1 for r in results if r.success)
        failed = total - passed
        
        return {
            'total_checks': total,
            'passed_checks': passed,
            'failed_checks': failed,
            'success_rate': passed / total if total > 0 else 0,
            'dry_run': self.dry_run,
            'details': [asdict(r) for r in results]
        }
    
    def _get_emergency_response_info(self, deployment_id: str) -> Dict[str, Any]:
        """Get emergency response information for deployment."""
        emergency_info = {
            'timeout_monitoring_active': False,
            'emergency_cleanup_performed': False,
            'resources_tracked': 0,
            'estimated_cost': 0.0,
            'dry_run': self.dry_run
        }
        
        try:
            if self.emergency_handler:
                emergency_info['timeout_monitoring_active'] = not self.emergency_handler.timeout_triggered
                
                # Get resource information
                if self.resource_tracker:
                    resources = self.resource_tracker.get_resources_by_deployment(deployment_id)
                    emergency_info['resources_tracked'] = len(resources)
                    emergency_info['estimated_cost'] = self.resource_tracker.estimate_total_cost(deployment_id)
                
                # Check if emergency cleanup was performed
                cleanup_results = [r for r in self.emergency_handler.cleanup_results if r.deployment_id == deployment_id]
                emergency_info['emergency_cleanup_performed'] = len(cleanup_results) > 0
                
        except Exception as e:
            emergency_info['error'] = str(e)
            self.logger.error(f"Failed to get emergency response info: {e}")
        
        return emergency_info
    
    def generate_enhanced_execution_plan(self, test_plan: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Generate enhanced execution plan with SSH and emergency response details."""
        base_plan = {
            'test_plan': test_plan,
            'enhanced_features': {
                'ssh_validation': True,
                'emergency_response': True,
                'resource_tracking': True,
                'timeout_monitoring': True
            },
            'dry_run': self.dry_run,
            'timeout_minutes': self.timeout_minutes
        }
        
        # Add SSH validation plans for each test
        ssh_validation_plans = []
        emergency_response_plans = []
        
        for test_case in test_plan:
            deployment_id = test_case['deployment_id']
            deploy_dir = self.work_dir / deployment_id
            
            # Create temporary components for plan generation
            temp_ssh_validator = SSHValidator(deploy_dir, dry_run=True)
            temp_emergency_handler = EmergencyHandler(deploy_dir, timeout_minutes=self.timeout_minutes, dry_run=True)
            
            # Get SSH validation plan
            ssh_plan = temp_ssh_validator.get_execution_plan()
            ssh_plan['deployment_id'] = deployment_id
            ssh_validation_plans.append(ssh_plan)
            
            # Get emergency response plan
            emergency_plan = temp_emergency_handler.get_emergency_plan(deployment_id)
            emergency_response_plans.append(emergency_plan)
        
        base_plan['ssh_validation_plans'] = ssh_validation_plans
        base_plan['emergency_response_plans'] = emergency_response_plans
        
        return base_plan
    
    def save_enhanced_execution_plan(self, test_plan: List[Dict[str, Any]], output_file: Path):
        """Save enhanced execution plan to JSON file."""
        plan = self.generate_enhanced_execution_plan(test_plan)
        
        with open(output_file, 'w') as f:
            json.dump(plan, f, indent=2, default=str)
        
        self.logger.info(f"Enhanced execution plan saved to {output_file}")
    
    def get_enhanced_results_summary(self) -> Dict[str, Any]:
        """Get comprehensive summary of enhanced test results."""
        if not self.enhanced_results:
            return {
                'status': 'no_results',
                'message': 'No enhanced tests executed yet',
                'dry_run': self.dry_run
            }
        
        # Count emergency events
        emergency_events = [r for r in self.enhanced_results if r.get('event_type') == 'emergency_cleanup']
        
        summary = {
            'total_enhanced_results': len(self.enhanced_results),
            'emergency_events': len(emergency_events),
            'dry_run': self.dry_run,
            'timeout_minutes': self.timeout_minutes,
            'enhanced_results': self.enhanced_results
        }
        
        return summary
    
    def run_tests_with_monitoring(self, test_plan: List[Dict[str, Any]], max_parallel: int = 1) -> List[Dict[str, Any]]:
        """Run tests with enhanced monitoring and emergency response."""
        self.logger.info(f"Starting enhanced test execution with monitoring")
        
        # Start monitoring for each test
        for test_case in test_plan:
            deployment_id = test_case['deployment_id']
            
            if self.emergency_handler and not self.dry_run:
                self.emergency_handler.start_timeout_monitoring(deployment_id)
        
        try:
            # Run tests using parent method
            results = super().run_tests(test_plan, max_parallel)
            
            # Add enhanced results to each test result
            for result in results:
                deployment_id = result['deployment_id']
                
                # Get SSH validation results
                if self.ssh_validator:
                    result['ssh_validation_summary'] = self.ssh_validator.get_results_summary()
                
                # Get emergency response summary
                if self.emergency_handler:
                    result['emergency_response_summary'] = self.emergency_handler.get_cleanup_summary()
                
                # Get resource tracking summary
                if self.resource_tracker:
                    result['resource_tracking_summary'] = {
                        'total_resources': len(self.resource_tracker.resources),
                        'estimated_cost': self.resource_tracker.estimate_total_cost(deployment_id)
                    }
            
            return results
            
        finally:
            # Stop all monitoring
            if self.emergency_handler and not self.dry_run:
                self.emergency_handler.stop_timeout_monitoring()
    
    def save_enhanced_results(self, results: List[Dict[str, Any]], total_time: float):
        """Save enhanced test results with additional metadata."""
        timestamp = time.strftime('%Y%m%d_%H%M%S')
        results_file = self.results_dir / f"enhanced_test_results_{timestamp}.json"
        
        summary = {
            'timestamp': timestamp,
            'total_tests': len(results),
            'passed': sum(1 for r in results if r['success']),
            'failed': sum(1 for r in results if not r['success']),
            'total_time': total_time,
            'dry_run': self.dry_run,
            'timeout_minutes': self.timeout_minutes,
            'enhanced_features': {
                'ssh_validation': True,
                'emergency_response': True,
                'resource_tracking': True
            },
            'enhanced_results_summary': self.get_enhanced_results_summary(),
            'results': results
        }
        
        with open(results_file, 'w') as f:
            json.dump(summary, f, indent=2, default=str)
        
        self.logger.info(f"Enhanced results saved to {results_file}")


def main():
    """Main function for enhanced E2E framework."""
    import argparse
    import tempfile
    import shutil
    import sys
    
    parser = argparse.ArgumentParser(description='Enhanced Exasol E2E Test Framework')
    parser.add_argument('action', choices=['plan', 'run'], help='Action to perform')
    parser.add_argument('--config', required=True, help='Path to test configuration file')
    parser.add_argument('--results-dir', help='Path to results directory (default: temporary directory)')
    parser.add_argument('--test-results-dir', help='Directory for unit test results (default: temporary directory)')
    parser.add_argument('--dry-run', action='store_true', default=True, help='Generate plan without executing (default: True)')
    parser.add_argument('--no-dry-run', action='store_true', help='Execute actual deployments (DANGEROUS)')
    parser.add_argument('--parallel', type=int, default=1, help='Maximum parallel executions')
    parser.add_argument('--timeout', type=int, default=30, help='Timeout in minutes for deployments')
    parser.add_argument('--output-plan', help='Save execution plan to file')
    parser.add_argument('--verbose', action='store_true', help='Show detailed test output')
    parser.add_argument('--keep-results', action='store_true', help='Keep temporary results directory')
    
    args = parser.parse_args()
    
    # Set up temporary directories if not specified
    temp_dirs = []
    cleanup_temp_dirs = []
    
    if not args.results_dir:
        temp_results_dir = tempfile.mkdtemp(prefix="exasol_e2e_results_")
        args.results_dir = temp_results_dir
        temp_dirs.append(temp_results_dir)
        if not args.keep_results:
            cleanup_temp_dirs.append(temp_results_dir)
    
    if not args.test_results_dir:
        temp_test_dir = tempfile.mkdtemp(prefix="exasol_e2e_tests_")
        args.test_results_dir = temp_test_dir
        temp_dirs.append(temp_test_dir)
        if not args.keep_results:
            cleanup_temp_dirs.append(temp_test_dir)
    
    # Cleanup function for temporary directories
    def cleanup_temp():
        for temp_dir in cleanup_temp_dirs:
            try:
                shutil.rmtree(temp_dir, ignore_errors=True)
            except Exception as e:
                if args.verbose:
                    print(f"Warning: Failed to cleanup {temp_dir}: {e}")
    
    # Register cleanup
    import atexit
    atexit.register(cleanup_temp)
    
    # Determine dry run mode
    dry_run = args.dry_run and not args.no_dry_run
    
    if not dry_run:
        print("⚠️  WARNING: Running in LIVE MODE - will create actual cloud resources!")
        response = input("Continue? (yes/no): ")
        if response.lower() != 'yes':
            print("Aborted.")
            return
    
    # Initialize enhanced framework
    framework = EnhancedE2ETestFramework(
        args.config, 
        Path(args.results_dir), 
        dry_run=dry_run,
        timeout_minutes=args.timeout
    )
    
    if args.action == 'plan':
        test_plan = framework.generate_test_plan(dry_run=True)
        
        # Generate enhanced execution plan
        enhanced_plan = framework.generate_enhanced_execution_plan(test_plan)
        
        print(f"\n{'='*60}")
        print("ENHANCED E2E TEST PLAN")
        print(f"{'='*60}")
        print(f"Total test cases: {len(test_plan)}")
        print(f"Dry run mode: {dry_run}")
        print(f"Timeout: {args.timeout} minutes")
        print(f"Enhanced features: SSH validation, Emergency response, Resource tracking")
        
        # Save plan if requested
        if args.output_plan:
            framework.save_enhanced_execution_plan(test_plan, Path(args.output_plan))
            if args.verbose:
                print(f"Enhanced execution plan saved to: {args.output_plan}")
        
        # Show results directory info
        if not args.verbose:
            print(f"\nResults directory: {args.results_dir}")
            if cleanup_temp_dirs:
                print(f"Note: Results will be cleaned up automatically. Use --keep-results to preserve.")
                print(f"      Or rerun with --results-dir {args.results_dir} to keep results.")
        
    elif args.action == 'run':
        test_plan = framework.generate_test_plan(dry_run=dry_run)
        
        if not dry_run:
            print(f"🚀 Starting enhanced E2E test execution ({len(test_plan)} tests)")
            results = framework.run_tests_with_monitoring(test_plan, max_parallel=args.parallel)
            framework.save_enhanced_results(results, time.time())
        else:
            print("🔍 DRY RUN MODE - Would execute the following enhanced tests:")
            for i, test in enumerate(test_plan):
                print(f"  {i+1}: {test['deployment_id']} - {test['parameters']}")
            
            # Show enhanced execution plan
            enhanced_plan = framework.generate_enhanced_execution_plan(test_plan)
            print(f"\nEnhanced features per test:")
            for i, ssh_plan in enumerate(enhanced_plan['ssh_validation_plans']):
                print(f"  Test {i+1}: {len(ssh_plan['validations'])} SSH validations")
            
            for i, emergency_plan in enumerate(enhanced_plan['emergency_response_plans']):
                print(f"  Test {i+1}: {len(emergency_plan['resources_to_cleanup'])} resources to track")


if __name__ == '__main__':
    main()