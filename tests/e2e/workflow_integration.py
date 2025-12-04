#!/usr/bin/env python3
"""
Integration layer for workflow-based testing into the existing e2e framework.

This module extends E2ETestFramework to handle 'workflow' test types.
"""

import logging
import time
from pathlib import Path
from typing import Dict, List, Any, Optional

from tests.e2e.workflow_engine import WorkflowExecutor, StepStatus


def add_workflow_support_to_framework(framework_instance):
    """
    Monkey-patch the E2ETestFramework to add workflow support.
    This is a non-invasive way to extend the framework.
    """
    original_run_single_test = framework_instance._run_single_test

    def enhanced_run_single_test(self, test_case: Dict[str, Any]) -> Dict[str, Any]:
        """Enhanced version that handles workflow test_type"""
        test_type = test_case.get('test_type', 'matrix')

        if test_type == 'workflow':
            return self._run_workflow_test(test_case)
        else:
            return original_run_single_test(test_case)

    # Add new method to framework
    framework_instance._run_workflow_test = lambda test_case: _run_workflow_test(
        framework_instance, test_case
    )

    # Replace original method
    framework_instance._run_single_test = lambda test_case: enhanced_run_single_test(
        framework_instance, test_case
    )


def _run_workflow_test(framework, test_case: Dict[str, Any]) -> Dict[str, Any]:
    """Execute a workflow-based test"""
    deployment_id = test_case['deployment_id']
    provider = test_case['provider']
    workflow_steps = test_case.get('workflow', [])

    test_output_dir = framework.tests_root / deployment_id
    test_output_dir.mkdir(parents=True, exist_ok=True)
    log_file = test_output_dir / 'test.log'
    framework._log_to_file(log_file, f"Starting workflow test {deployment_id} ({provider})")

    # Update progress tracking
    with framework._progress_lock:
        framework._current_deployment = deployment_id
        framework._current_step = "workflow"

    framework._log_deployment_step(deployment_id, "STARTED", "workflow")

    result = {
        'deployment_id': deployment_id,
        'suite': test_case['suite'],
        'provider': provider,
        'test_type': 'workflow',
        'success': False,
        'duration': 0,
        'error': None,
        'logs': [],
        'workflow_steps': [],
        'log_file': str(log_file),
        'log_directory': str(test_output_dir),
        'config_path': test_case.get('config_path', str(framework.config_path))
    }

    start_time = time.time()

    # Create deployment directory
    deploy_dir = framework.work_dir / deployment_id
    deploy_dir.mkdir(exist_ok=True)
    result['deployment_dir'] = str(deploy_dir)

    emergency_handler = framework._initialize_emergency_handler(deployment_id, deploy_dir)
    resource_tracker = framework._initialize_resource_tracker(deploy_dir, emergency_handler)

    try:
        params = test_case.get('parameters', {})
        result['parameters'] = params

        # Create workflow executor
        def log_callback(msg: str):
            framework._log_to_file(log_file, msg)
            with framework._progress_lock:
                framework._current_step = msg[:30]  # Truncate for display
            framework._render_progress(
                framework._completed_tests,
                framework._total_tests,
                deployment_id,
                msg[:30]
            )

        executor = WorkflowExecutor(
            deploy_dir=deploy_dir,
            provider=provider,
            logger=framework.logger,
            log_callback=log_callback
        )

        # Execute workflow
        framework.logger.info(f"Executing workflow with {len(workflow_steps)} steps")
        framework._log_to_file(log_file, f"Workflow has {len(workflow_steps)} steps")

        step_results = executor.execute_workflow(workflow_steps, params)

        # Convert step results to serializable format
        for step_result in step_results:
            step_dict = {
                'step_type': step_result.step_type,
                'description': step_result.description,
                'status': step_result.status.value,
                'duration': step_result.duration,
                'error': step_result.error,
                'result': step_result.result,
                'validation_results': step_result.validation_results,
                'target_node': step_result.target_node,
                'method': step_result.method
            }
            result['workflow_steps'].append(step_dict)

            # Log each step completion
            status_symbol = "✓" if step_result.status == StepStatus.COMPLETED else "✗"
            framework._log_to_file(
                log_file,
                f"{status_symbol} Step: {step_result.description} - "
                f"{step_result.status.value} ({step_result.duration:.1f}s)"
            )

        # Determine overall success
        failed_steps = [s for s in step_results if s.status == StepStatus.FAILED]
        result['success'] = len(failed_steps) == 0

        if failed_steps:
            result['error'] = f"{len(failed_steps)} workflow step(s) failed"
            for failed in failed_steps:
                result['logs'].append(f"Failed: {failed.description} - {failed.error}")

    except Exception as e:
        result['error'] = str(e)
        result['logs'].append(f"Workflow execution error: {e}")
        framework._log_to_file(log_file, f"Workflow test {deployment_id} failed: {e}")
        if emergency_handler:
            try:
                emergency_handler.emergency_cleanup(deployment_id)
            except Exception as cleanup_error:
                framework._log_to_file(log_file, f"Emergency cleanup error: {cleanup_error}")

    finally:
        result['duration'] = time.time() - start_time

        # Cleanup
        try:
            framework.logger.info(f"Starting cleanup for {deployment_id}")
            framework._log_to_file(log_file, "Starting cleanup phase")
            
            with framework._progress_lock:
                framework._current_step = "cleaning up"
            framework._log_deployment_step(deployment_id, "cleaning up", "in progress")
            framework._render_progress(
                framework._completed_tests,
                framework._total_tests,
                deployment_id,
                "cleaning up"
            )

            framework.logger.info(f"Calling _cleanup_deployment for {deploy_dir}")
            retained_dir = framework._cleanup_deployment(
                deploy_dir,
                provider,
                log_file,
                keep_artifacts=not result['success']
            )
            
            framework.logger.info(f"Cleanup completed, retained_dir={retained_dir}")
            framework._log_to_file(log_file, f"Cleanup completed, retained_dir={retained_dir}")
            
            if retained_dir:
                result['retained_deployment_dir'] = str(retained_dir)
                framework._log_deployment_step(deployment_id, "cleaning up", "retained artifacts")
            else:
                result['retained_deployment_dir'] = None
                framework._log_deployment_step(deployment_id, "cleaning up", "completed")
        except Exception as e:
            framework.logger.error(f"Cleanup error: {e}", exc_info=True)
            result['logs'].append(f"Cleanup error: {e}")
            framework._log_to_file(log_file, f"Cleanup error: {e}")
            framework._log_deployment_step(deployment_id, "cleaning up", "failed")
            # Ensure retained_deployment_dir is set even on error
            result['retained_deployment_dir'] = None

        if emergency_handler:
            emergency_handler.stop_timeout_monitoring()
            result['emergency_summary'] = framework._get_emergency_summary(emergency_handler)
        else:
            result['emergency_summary'] = None

        # Log completion
        status = "COMPLETED" if result['success'] else "FAILED"
        framework._log_deployment_step(deployment_id, status, f"duration: {result['duration']:.1f}s")

        # Clear current deployment from progress tracking
        with framework._progress_lock:
            framework._current_deployment = None
            framework._current_step = None

    return result


def parse_workflow_test_plans(config: Dict[str, Any], suite_name: str,
                              suite_config: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Parse workflow-based test configuration into test plans.

    For workflow tests, we don't generate combinations - we execute
    the workflow exactly as specified with the given parameters.
    """
    test_plans = []

    if suite_config.get('test_type') != 'workflow':
        return test_plans

    provider = suite_config['provider']
    params = suite_config.get('parameters', {})
    workflow = suite_config.get('workflow', [])
    description = suite_config.get('description', '')

    # Use suite name as deployment ID (simple and readable)
    deployment_id = suite_name

    test_plan = {
        'deployment_id': deployment_id,
        'suite': suite_name,
        'provider': provider,
        'test_type': 'workflow',
        'description': description,
        'parameters': params,
        'workflow': workflow,
        'config_path': config.get('_config_path', 'unknown')
    }

    test_plans.append(test_plan)

    return test_plans
