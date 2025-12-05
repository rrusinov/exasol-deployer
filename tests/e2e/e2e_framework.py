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
import atexit
import concurrent.futures
import http.client
import html
import json
import logging
import os
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Any, Optional, Set, Tuple, Callable, Union

# Try to import SSH validator for live system validation
try:
    from tests.e2e.ssh_validator import SSHValidator
    SSH_VALIDATION_AVAILABLE = True
except ImportError:
    SSH_VALIDATION_AVAILABLE = False
    SSHValidator = None

try:
    from tests.e2e.emergency_handler import EmergencyHandler, ResourceTracker, ResourceInfo
    EMERGENCY_TOOLING_AVAILABLE = True
except ImportError:
    EMERGENCY_TOOLING_AVAILABLE = False
    EmergencyHandler = ResourceTracker = ResourceInfo = None

try:
    from config_schema import (
        validate_workflow_step,
        validate_validation_check,
        validate_sut_parameters
    )
    CONFIG_VALIDATION_AVAILABLE = True
except ImportError:
    CONFIG_VALIDATION_AVAILABLE = False


class NotificationManager:
    """Collects notification events and persists them to disk."""

    def __init__(self, results_dir: Path, config: Optional[Dict[str, Any]] = None):
        config = config or {}
        self.results_dir = Path(results_dir)
        self.enabled = bool(config.get('enabled', True))
        self.include_failures = bool(config.get('notify_on_failures', True))
        self.include_performance = bool(config.get('notify_on_slow_tests', True))
        self.slow_test_threshold = int(config.get('slow_test_threshold_seconds', 900))
        self.events: List[Dict[str, Any]] = []

    def record_result(self, result: Dict[str, Any]):
        if not self.enabled:
            return
        reason = None
        if self.include_failures and not result.get('success', False):
            reason = 'failure'
        elif (
            self.include_performance
            and result.get('duration', 0) >= self.slow_test_threshold
        ):
            reason = 'performance'
        if not reason:
            return
        event = {
            'deployment_id': result.get('deployment_id'),
            'reason': reason,
            'success': result.get('success', False),
            'duration': result.get('duration', 0),
            'error': result.get('error'),
            'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ')
        }
        self.events.append(event)

    def flush_to_disk(self) -> Optional[Dict[str, Any]]:
        if not self.enabled or not self.events:
            return None
        timestamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
        notifications_file = self.results_dir / f"notifications_{timestamp}.json"
        log_file = self.results_dir / 'notifications.log'
        with open(notifications_file, 'w', encoding='utf-8') as handle:
            json.dump(self.events, handle, indent=2)
        with open(log_file, 'a', encoding='utf-8') as handle:
            for event in self.events:
                handle.write(
                    f"[{event['timestamp']}] {event['deployment_id']} "
                    f"({event['reason']}): success={event['success']} "
                    f"duration={event['duration']:.1f}s error={event.get('error','') or 'n/a'}\n"
                )
        summary = {
            'event_count': len(self.events),
            'file': str(notifications_file),
            'log_file': str(log_file),
            'slow_test_threshold_seconds': self.slow_test_threshold,
            'generated_at': timestamp
        }
        self.events = []
        return summary


class ResourceQuotaMonitor:
    """Ensures planned tests stay within configured resource limits."""

    DEFAULT_LIMITS = {
        'max_cluster_size_per_test': 8,
        'max_total_instances': 32,
        'max_total_data_volume_gb': 20000,
        'max_parallel_executions': 6,
        'default_cluster_size': 1,
        'default_data_volumes_per_node': 1,
        'default_data_volume_size': 100,
        'deployment_timeout_minutes': 45
    }



    def __init__(self, limits: Optional[Dict[str, Any]] = None):
        limits = limits or {}
        self.limits = {**self.DEFAULT_LIMITS, **limits}

    def evaluate_plan(self, test_plan: List[Dict[str, Any]], max_parallel: int) -> Dict[str, Any]:
        metrics = {
            'total_tests': len(test_plan),
            'total_instances': 0,
            'max_cluster_size': 0,
            'total_data_volume_gb': 0,
            'max_parallel_requested': max_parallel or len(test_plan)
        }

        for test in test_plan:
            params = test.get('parameters', {})
            cluster_size = int(params.get('cluster_size', self.limits['default_cluster_size']))
            dv_per_node = int(params.get('data_volumes_per_node', self.limits['default_data_volumes_per_node']))
            dv_size = int(params.get('data_volume_size', self.limits['default_data_volume_size']))
            metrics['total_instances'] += cluster_size
            metrics['max_cluster_size'] = max(metrics['max_cluster_size'], cluster_size)
            metrics['total_data_volume_gb'] += cluster_size * dv_per_node * dv_size
            if cluster_size > self.limits['max_cluster_size_per_test']:
                raise ValueError(
                    f"cluster_size {cluster_size} exceeds max per test "
                    f"({self.limits['max_cluster_size_per_test']})"
                )

        self._assert_limit(
            metrics['total_instances'],
            self.limits['max_total_instances'],
            'total instances'
        )
        self._assert_limit(
            metrics['total_data_volume_gb'],
            self.limits['max_total_data_volume_gb'],
            'total data volume (GB)'
        )
        if metrics['max_parallel_requested'] > self.limits['max_parallel_executions']:
            raise ValueError(
                f"max_parallel {metrics['max_parallel_requested']} exceeds limit "
                f"({self.limits['max_parallel_executions']})"
            )
        return metrics



    @staticmethod
    def _assert_limit(actual: float, limit: float, label: str):
        if actual > limit:
            raise ValueError(f"{label} {actual} exceeds limit {limit}")


class HTMLReportGenerator:
    """Creates HTML reports alongside JSON summaries."""

    def __init__(self, output_dir: Path):
        self.output_dir = Path(output_dir)

    def generate(self, summary: Dict[str, Any], filename: str):
        self.output_dir.mkdir(parents=True, exist_ok=True)
        rows = []
        for result in summary.get('results', []):
            status = 'PASS' if result.get('success') else 'FAIL'
            row_class = 'pass' if result.get('success') else 'fail'
            error = html.escape(result.get('error') or '')
            suite_name = html.escape(result.get('suite', result.get('deployment_id', 'n/a')))
            db_version = html.escape(result.get('db_version', 'default'))
            
            # Build workflow steps display
            steps_html = []
            for step in result.get('steps', []):
                step_status = step.get('status', 'unknown')
                step_class = 'pass' if step_status == 'completed' else 'fail' if step_status == 'failed' else 'pending'
                step_name = html.escape(step.get('step', 'unknown'))
                step_duration = step.get('duration', 0)
                step_error = html.escape(step.get('error') or '')
                steps_html.append(
                    f"<div class='step step-{step_class}'>"
                    f"<strong>{step_name}</strong>: {step_status} ({step_duration:.1f}s)"
                    f"{(' - ' + step_error) if step_error else ''}"
                    f"</div>"
                )
            steps_display = ''.join(steps_html) if steps_html else '<div class=\"step\">No steps recorded</div>'
            
            # Build parameters display
            params = result.get('parameters', {})
            params_items = [f"{k}={v}" for k, v in params.items()]
            params_display_short = html.escape(', '.join(params_items[:5]))  # Show first 5 in table
            params_display_full = html.escape(', '.join(params_items)) if params_items else 'N/A'  # Show all in details
            
            # Description from SUT
            sut_desc = html.escape(result.get('sut_description') or '')
            
            rows.append(
                f"<tr class='{row_class}'>"
                f"<td><strong>{suite_name}</strong><br/><small>{sut_desc}</small></td>"
                f"<td>{html.escape(result.get('provider') or '')}</td>"
                f"<td>{db_version}</td>"
                f"<td><small>{params_display_short}</small></td>"
                f"<td>{result.get('duration', 0):.1f}s</td>"
                f"<td>{status}</td>"
                f"<td>{error}</td>"
                "</tr>"
                f"<tr class='{row_class}-details'><td colspan='7'><details><summary>Steps & Config</summary>"
                f"<div class='config-section'><strong>Parameters:</strong> {params_display_full}</div>"
                f"{steps_display}</details></td></tr>"
            )
        rows_html = '\n'.join(rows)
        html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Exasol E2E Test Report</title>
<style>
body {{ font-family: Arial, sans-serif; margin: 2rem; }}
table {{ border-collapse: collapse; width: 100%; margin-top: 1rem; }}
th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
th {{ background-color: #4CAF50; color: white; }}
tr.pass {{ background-color: #f6ffed; }}
tr.fail {{ background-color: #fff1f0; }}
tr.pass-details, tr.fail-details {{ background-color: #fafafa; }}
details {{ margin: 0.5rem 0; }}
summary {{ cursor: pointer; font-weight: bold; padding: 0.5rem; background: #f0f0f0; }}
.step {{ padding: 0.3rem; margin: 0.2rem 0; border-left: 3px solid #ccc; padding-left: 0.5rem; }}
.step-pass {{ border-left-color: #52c41a; }}
.step-fail {{ border-left-color: #f5222d; }}
.step-pending {{ border-left-color: #faad14; }}
.summary-box {{ background: #f0f0f0; padding: 1rem; border-radius: 5px; margin-bottom: 1rem; }}
.summary-box h2 {{ margin-top: 0; }}
.config-section {{ background: #f9f9f9; padding: 0.5rem; margin: 0.3rem 0; border-radius: 3px; }}
</style>
</head>
<body>
<h1>Exasol E2E Test Report</h1>
<div class="summary-box">
<h2>Summary</h2>
<p><strong>Execution:</strong> {summary.get('execution_dir', 'N/A')}</p>
<p><strong>Database Version:</strong> {summary.get('db_version', 'default')} | 
   <strong>Provider:</strong> {', '.join(summary.get('provider')) if isinstance(summary.get('provider'), list) else summary.get('provider', 'N/A')}</p>
<p><strong>Total tests:</strong> {summary.get('total_tests', 0)} | 
   <strong>Passed:</strong> {summary.get('passed', 0)} | 
   <strong>Failed:</strong> {summary.get('failed', 0)} | 
   <strong>Total time:</strong> {summary.get('total_time', 0):.1f}s</p>
</div>
<table>
<thead><tr><th>Suite</th><th>Provider</th><th>DB Version</th><th>Parameters</th><th>Duration</th><th>Status</th><th>Error</th></tr></thead>
<tbody>
{rows_html}
</tbody>
        </table>
        </body>
        </html>"""
        report_path = self.output_dir / filename
        with open(report_path, 'w', encoding='utf-8') as handle:
            handle.write(html_content)
        latest_path = self.output_dir / 'latest_results.html'
        with open(latest_path, 'w', encoding='utf-8') as handle:
            handle.write(html_content)


class E2ETestFramework:
    """Main E2E test framework class."""

    def __init__(self, config_path: str, results_dir: Optional[Path] = None, db_version: Optional[str] = None, stop_on_error: bool = False):
        self.config_path = Path(config_path)
        self.db_version = db_version  # Optional database version override
        self.stop_on_error = stop_on_error  # Stop execution on first test failure
        
        # Create execution-timestamp directory: ./tmp/tests/e2e-YYYYMMDD-HHMMSS/
        self.execution_timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        # Use absolute path to ensure logs go to correct location regardless of cwd
        base_dir = Path('./tmp/tests').resolve()
        self.results_dir = results_dir if results_dir else (base_dir / f'e2e-{self.execution_timestamp}')
        self.results_dir.mkdir(parents=True, exist_ok=True)
        
        # Create deployments directory under results directory
        self.work_dir = self.results_dir / 'deployments'
        self.work_dir.mkdir(parents=True, exist_ok=True)
        self.results = []
        # Run CLI commands from repository root so ./exasol can be found
        self.repo_root = Path(__file__).resolve().parents[2]
        self.generated_ids: Set[str] = set()
        self.suite_run_counts: Dict[str, int] = {}  # Track reruns per suite
        self._progress_lock = threading.Lock()
        
        # Progress tracking
        self._current_deployment: Optional[str] = None
        self._current_step: Optional[str] = None
        self._completed_tests: int = 0
        self._total_tests: int = 0

        # Setup logging
        self._setup_logging()
        self.config = self._load_config()
        
        # Validate configuration
        self._validate_configuration()
        
        self.live_mode = bool(self.config.get('live_mode', False))
        self.enable_live_validation = bool(self.config.get('enable_live_validation', True))
        resource_limits = self.config.get('resource_limits', {})
        notifications_cfg = self.config.get('notifications', {})
        self.quota_monitor = ResourceQuotaMonitor(resource_limits)
        self.notification_manager = NotificationManager(self.results_dir, notifications_cfg)
        self.html_report_generator = HTMLReportGenerator(self.results_dir)
        self.resource_plan_metrics: Dict[str, Any] = {}
        
        # Register cleanup function to be called on exit
        atexit.register(self._cleanup)
        
        # Register cleanup function to be called on exit
        atexit.register(self._cleanup)

    def _resolve_db_version(self, suite_db_version: Optional[Union[str, List[str]]]) -> Optional[str]:
        """Resolve database version with fallback support.
        
        Priority:
        1. CLI argument (self.db_version)
        2. SUT config db_version (can be a list with fallbacks)
        3. None (uses exasol CLI default)
        
        If suite_db_version is a list, check each version in order and use the first that exists.
        
        Special handling for 'default-local' alias:
        - If 'default-local' exists, extract the actual version name from the output
        """
        # CLI argument has highest priority (but still needs alias resolution)
        if self.db_version:
            return self._resolve_version_alias(self.db_version)
        
        # No SUT config db_version specified
        if not suite_db_version:
            return None
        
        # Single version string
        if isinstance(suite_db_version, str):
            return self._resolve_version_alias(suite_db_version)
        
        # List of versions with fallback
        if isinstance(suite_db_version, list):
            # Check each version in order using exasol CLI
            for version in suite_db_version:
                if self._check_version_exists(version):
                    resolved = self._resolve_version_alias(version)
                    self.logger.info(f"Using database version: {resolved}")
                    return resolved
            
            # If no version found, use the last one as fallback
            fallback = self._resolve_version_alias(suite_db_version[-1])
            self.logger.warning(f"None of the versions {suite_db_version} found, using last: {fallback}")
            return fallback
        
        return None
    
    def _resolve_version_alias(self, version: str) -> str:
        """Resolve version aliases like 'default-local' to actual version names.
        
        If version is 'default-local', extract the actual version from the
        --list-versions output by finding the line with (default-local) marker.
        """
        if version != 'default-local':
            return version
        
        try:
            result = subprocess.run(
                ['./exasol', 'init', '--list-versions'],
                capture_output=True,
                text=True,
                timeout=10,
                cwd=self.repo_root
            )
            if result.returncode == 0:
                output = result.stdout + result.stderr
                # Look for line with (default-local) marker
                # Format: "[INFO]   [+] exasol-2025.1.8-local [x86_64] (default-local)"
                for line in output.split('\n'):
                    if '(default-local)' in line:
                        # Extract version name
                        import re
                        # Remove ANSI color codes
                        clean_line = re.sub(r'\x1b\[[0-9;]+m', '', line)
                        # Look for pattern: [+] or [x] followed by version name
                        match = re.search(r'\[([\+x])\]\s+(\S+)', clean_line)
                        if match:
                            actual_version = match.group(2)
                            self.logger.debug(f"Resolved 'default-local' to '{actual_version}'")
                            return actual_version
        except Exception as e:
            self.logger.debug(f"Failed to resolve default-local alias: {e}")
        
        # Fallback: return as-is
        return version
    
    def _check_version_exists(self, version: str) -> bool:
        """Check if a database version exists using exasol CLI.
        
        Also handles special aliases like 'default-local' by looking for
        the (default-local) marker in the output.
        """
        try:
            result = subprocess.run(
                ['./exasol', 'init', '--list-versions'],
                capture_output=True,
                text=True,
                timeout=10,
                cwd=self.repo_root
            )
            if result.returncode == 0:
                output = result.stdout + result.stderr
                
                # Special handling for 'default-local' alias
                # Look for "(default-local)" marker in the output
                if version == 'default-local':
                    return '(default-local)' in output
                
                # For regular versions, check if version name appears in output
                return version in output
        except Exception as e:
            self.logger.debug(f"Failed to check version {version}: {e}")
        
        return False

    def _setup_logging(self):
        """Setup logging configuration."""
        # Ensure results directory exists before creating log file
        try:
            self.results_dir.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            # If directory creation fails, create fallback in temp
            import tempfile
            fallback_dir = Path(tempfile.mkdtemp(prefix="exasol_e2e_logs_"))
            self.results_dir = fallback_dir / 'results'
            self.results_dir.mkdir(parents=True, exist_ok=True)

        log_file = self.results_dir / f"e2e_test_{self.execution_timestamp}.log"
        # Ensure parent directory exists for FileHandler
        log_file.parent.mkdir(parents=True, exist_ok=True)

        self.logger = logging.getLogger('e2e_framework')
        self.logger.setLevel(logging.INFO)

        # Remove any existing handlers for this logger
        for handler in self.logger.handlers[:]:
            handler.close()
            self.logger.removeHandler(handler)

        self.file_handler = logging.FileHandler(log_file)
        self.execution_log_file = log_file

        # Create formatter
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        
        # Configure file handler
        self.file_handler.setFormatter(formatter)
        self.file_handler.setLevel(logging.INFO)
        
        # Add file handler to this logger
        self.logger.addHandler(self.file_handler)
        
        # Create a custom stdout handler that respects progress rendering
        class ProgressAwareHandler(logging.StreamHandler):
            """StreamHandler that clears progress line before logging"""
            def __init__(self, progress_lock, stream=None):
                super().__init__(stream)
                self.progress_lock = progress_lock
                
            def emit(self, record):
                try:
                    with self.progress_lock:
                        # Clear current line before logging
                        self.stream.write('\r\033[K')
                        super().emit(record)
                        self.stream.flush()
                except Exception:
                    self.handleError(record)
        
        # Also add to root logger if no handlers exist yet (for stdout)
        root_logger = logging.getLogger()
        if not root_logger.handlers:
            # Add custom stdout handler to root logger
            stdout_handler = ProgressAwareHandler(self._progress_lock, sys.stdout)
            stdout_handler.setFormatter(formatter)
            stdout_handler.setLevel(logging.INFO)
            root_logger.addHandler(stdout_handler)
            root_logger.setLevel(logging.INFO)
        
        # Logging is now ready - messages will be written when called

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
        
        # If using modular config structure, load and merge SUT/workflow files
        if 'test_suites' in config and isinstance(config['test_suites'], list):
            config = self._load_modular_config(config)
        
        return config
    
    def _load_modular_config(self, provider_config: Dict[str, Any]) -> Dict[str, Any]:
        """Load modular configuration with separate SUT and workflow files."""
        configs_dir = self.config_path.parent
        provider = provider_config.get('provider', 'unknown')
        merged_suites = {}
        
        for idx, test_suite in enumerate(provider_config.get('test_suites', [])):
            sut_path = configs_dir / test_suite['sut']
            workflow_path = configs_dir / test_suite['workflow']
            
            # Extract names from file paths (without extension)
            # e.g., "sut/aws-4n.json" -> "aws-4n"
            sut_name = Path(test_suite['sut']).stem
            workflow_name = Path(test_suite['workflow']).stem
            
            # Check if files exist
            if not sut_path.exists():
                raise FileNotFoundError(f"SUT config file not found: {sut_path}")
            if not workflow_path.exists():
                raise FileNotFoundError(f"Workflow config file not found: {workflow_path}")
            
            # Load SUT config
            with open(sut_path, 'r', encoding='utf-8') as f:
                sut_config = json.load(f)
            
            # Load workflow config
            with open(workflow_path, 'r', encoding='utf-8') as f:
                workflow_config = json.load(f)
            
            # Create suite name from filenames (not from config fields)
            suite_name = f"{sut_name}_{workflow_name}"
            
            # Merge into test suite structure expected by framework
            merged_suites[suite_name] = {
                'provider': sut_config.get('provider', provider),
                'test_type': 'workflow',
                'description': f"{sut_config.get('description', sut_name)} + {workflow_config.get('description', workflow_name)}",
                'parameters': sut_config.get('parameters', {}),
                'workflow': workflow_config.get('steps', []),
                'db_version': sut_config.get('db_version')  # Pass through db_version from SUT config
            }
        
        # Return config in the format expected by generate_test_plan
        return {
            'provider': provider,
            'description': provider_config.get('description', ''),
            'max_concurrent_nodes': provider_config.get('max_concurrent_nodes', 0),
            'test_suites': merged_suites  # This is the correct key
        }

    def _validate_configuration(self):
        """Validate all test suite configurations for correctness."""
        if not CONFIG_VALIDATION_AVAILABLE:
            self.logger.warning("Configuration validation module not available, skipping validation")
            return
        
        all_errors = []
        
        for suite_name, suite_config in self.config.get('test_suites', {}).items():
            suite_errors = []
            provider = suite_config.get('provider', 'unknown')
            
            # Validate parameters
            if 'parameters' in suite_config:
                param_errors = validate_sut_parameters(suite_config['parameters'], provider)
                if param_errors:
                    suite_errors.append(f"Parameter validation errors:")
                    suite_errors.extend([f"  - {err}" for err in param_errors])
            
            # Validate workflow steps
            workflow = suite_config.get('workflow', [])
            for step_idx, step in enumerate(workflow):
                step_errors = validate_workflow_step(step, provider)
                if step_errors:
                    suite_errors.append(f"Step {step_idx + 1} ({step.get('step', 'unknown')}) validation errors:")
                    suite_errors.extend([f"  - {err}" for err in step_errors])
                
                # Validate validation checks within validate steps
                if step.get('step') == 'validate' and 'checks' in step:
                    for check_idx, check in enumerate(step['checks']):
                        check_errors = validate_validation_check(check)
                        if check_errors:
                            suite_errors.append(f"Step {step_idx + 1}, check {check_idx + 1} ('{check}') validation errors:")
                            suite_errors.extend([f"  - {err}" for err in check_errors])
            
            if suite_errors:
                all_errors.append(f"\nSuite '{suite_name}':")
                all_errors.extend(suite_errors)
        
        if all_errors:
            error_msg = "\n" + "="*80 + "\n"
            error_msg += "CONFIGURATION VALIDATION FAILED\n"
            error_msg += "="*80 + "\n"
            error_msg += "\n".join(all_errors)
            error_msg += "\n" + "="*80 + "\n"
            self.logger.error(error_msg)
            print(error_msg, file=sys.stderr)
            raise ValueError("Configuration validation failed. Please fix the errors above.")

    def _validate_config_keys(self, config: Dict[str, Any]):
        """Validate configuration for misspelled keys."""
        valid_keys = {
            'test_suites',
            'provider',
            'description',
            'sut',
            'workflow',
            'max_concurrent_nodes',
            'parameters',
            'combinations',
            'cluster_size',
            'instance_type',
            'data_volumes_per_node',
            'data_volume_size',
            'root_volume_size',
            'sut_name',
            'workflow_name',
            'steps',
            'step',
            'checks',
            'target_node',
            'method',
            'allow_failures',
            'retry',
            'max_attempts',
            'delay_seconds',
            'test_type',
            'requirements'
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
                    if not (path == 'test_suites' or 'parameters' in path or 'workflow' in path or 'steps' in path):
                        if key not in valid_keys:
                            self.logger.warning(f"Unknown key in config at {current_path}: '{key}'")
                    check_keys(value, current_path)
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    check_keys(item, f"{path}[{i}]")

        check_keys(config)

    def _slugify(self, value: str) -> str:
        slug = ''.join(c.lower() if c.isalnum() or c in ('-', '_') else '-' for c in str(value))
        slug = slug.replace('_', '-')
        while '--' in slug:
            slug = slug.replace('--', '-')
        return slug.strip('-') or 'value'

    def _build_deployment_id(self, suite_name: str, provider: str, combo: Dict[str, Any]) -> str:
        base = f"{self._slugify(suite_name)}-{self._slugify(provider)}"
        param_bits = []
        for key in sorted(combo.keys()):
            value = combo[key]
            display_value = str(value).replace('/', '-')
            param_bits.append(f"{self._slugify(key)}_{self._slugify(display_value)}")
        param_segment = '-'.join(param_bits) if param_bits else 'default'
        candidate = f"{base}-{param_segment}"
        if len(candidate) > 120:
            candidate = candidate[:117] + '...'

        final_name = candidate
        suffix = 2
        while final_name in self.generated_ids:
            final_name = f"{candidate}-{suffix}"
            suffix += 1
        self.generated_ids.add(final_name)
        return final_name

    def _provider_supports_spot(self, provider: str) -> bool:
        """Return True if the provider supports spot/preemptible instances."""
        normalized = provider.lower()
        return normalized in {'aws', 'azure', 'gcp'}

    def generate_test_plan(
        self,
        dry_run: bool = False,
        providers: Optional[Set[str]] = None,
        only_tests: Optional[Set[str]] = None
    ) -> List[Dict[str, Any]]:
        """Generate test plan from configuration parameters."""
        test_plan = []

        for suite_name, suite_config in self.config.get('test_suites', {}).items():
            provider_name = suite_config.get('provider', '').lower()
            if providers and provider_name not in providers:
                continue
            
            # Each suite has a single set of parameters (no combinations)
            parameters = suite_config.get('parameters', {})
            # Use suite name directly as deployment ID (simple and readable)
            deployment_id = suite_name
            # Match by suite name or deployment ID
            if only_tests and suite_name not in only_tests and deployment_id not in only_tests:
                continue
            
            test_case = {
                'suite': suite_name,
                'provider': suite_config['provider'],
                'test_type': suite_config.get('test_type', 'workflow'),
                'parameters': parameters.copy(),
                'deployment_id': deployment_id,
                'config_path': str(self.config_path),
                'workflow': suite_config.get('workflow', []),
                'sut_description': suite_config.get('sut_description', ''),
                'db_version': suite_config.get('db_version')
            }
            if self._provider_supports_spot(suite_config['provider']):
                test_case['parameters'].setdefault('enable_spot_instances', True)
            test_plan.append(test_case)

        if dry_run:
            print(f"Dry run: Generated {len(test_plan)} test cases")
            for i, test in enumerate(test_plan):
                print(f"  {i+1}: {test['deployment_id']} - {test['parameters']}")
        
        return test_plan

    def run_tests(self, test_plan: List[Dict[str, Any]], max_parallel: int = 1) -> List[Dict[str, Any]]:
        """Execute tests with resource-aware scheduling.
        
        Args:
            test_plan: List of test cases to execute
            max_parallel: CLI override for parallelism (0 = use config limit)
        
        Resource-aware scheduling:
        - Uses max_concurrent_nodes from provider config to limit total nodes in use
        - Schedules tests based on cluster_size to optimize resource usage
        - Example: max_concurrent_nodes=4 allows 1x4n OR 1x3n+1x1n OR 2x2n OR 4x1n
        """
        results = []
        start_time = time.time()

        if not test_plan:
            self.logger.warning("No tests to execute.")
            return results

        # Print execution directory info
        print(f"Results will be saved to: {self.results_dir.absolute()}")
        
        # Determine effective parallelism
        config_max_nodes = self.config.get('max_concurrent_nodes', 0)
        
        if max_parallel <= 0:
            # Use config limit or unlimited
            if config_max_nodes > 0:
                # Resource-aware scheduling enabled
                effective_parallel = len(test_plan)  # Allow scheduling all tests
                self.logger.info(f"Using resource-aware scheduling: max {config_max_nodes} concurrent nodes")
            else:
                # No limit configured, run all in parallel
                effective_parallel = max(1, len(test_plan))
        else:
            # CLI override: use traditional max_parallel approach
            effective_parallel = max_parallel
            config_max_nodes = 0  # Disable resource-aware scheduling

        try:
            self.resource_plan_metrics = self.quota_monitor.evaluate_plan(test_plan, effective_parallel)
        except ValueError as limit_error:
            self.logger.error(f"Resource quota limit exceeded: {limit_error}")
            raise

        # Set total tests for progress tracking
        with self._progress_lock:
            self._total_tests = len(test_plan)
        
        self.logger.info(f"Starting test execution with {len(test_plan)} tests, max_parallel={effective_parallel}")
        self._render_progress(0, len(test_plan))

        # Use resource-aware executor if node limit is configured
        if config_max_nodes > 0:
            results = self._run_tests_with_resource_scheduling(test_plan, config_max_nodes)
        else:
            results = self._run_tests_with_thread_pool(test_plan, effective_parallel)

        total_time = time.time() - start_time
        print()  # newline after progress bar
        self._save_results(results, total_time)
        self._print_summary(results, total_time)

        return results

    def _run_tests_with_thread_pool(self, test_plan: List[Dict[str, Any]], max_workers: int) -> List[Dict[str, Any]]:
        """Execute tests using traditional thread pool with fixed max_workers."""
        results = []
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_test = {executor.submit(self._run_single_test, test): test for test in test_plan}
            completed = 0
            for future in concurrent.futures.as_completed(future_to_test):
                result = future.result()
                results.append(result)
                self.notification_manager.record_result(result)
                completed += 1
                status = 'PASS' if result['success'] else 'FAIL'
                
                # If test failed, try to clean up deployment to free resources
                if not result['success']:
                    self.logger.warning(f"Test {result['deployment_id']} FAILED - attempting cleanup")
                    deploy_dir = Path(result.get('deployment_dir', ''))
                    if deploy_dir.exists():
                        try:
                            self._cleanup_failed_deployment(deploy_dir, result['deployment_id'])
                            self.logger.info(f"Cleanup completed for {result['deployment_id']}")
                        except Exception as cleanup_err:
                            self.logger.error(f"Cleanup failed for {result['deployment_id']}: {cleanup_err}")
                    
                    # Stop execution if --stop-on-error is set
                    if self.stop_on_error:
                        self.logger.error("Stopping execution due to test failure (--stop-on-error)")
                        # Cancel remaining futures
                        for remaining_future in future_to_test:
                            if not remaining_future.done():
                                remaining_test = future_to_test[remaining_future]
                                self.logger.info(f"Waiting for running test: {remaining_test['deployment_id']}")
                        # Let running tests complete, but don't start new ones
                        # Future iterations will be skipped as we break after this
                        break
                
                self.logger.info(f"Completed: {result['deployment_id']} - {status} ({result['duration']:.1f}s)")
                
                # Update completed count and clear current deployment
                with self._progress_lock:
                    self._completed_tests = completed
                    self._current_deployment = None
                    self._current_step = None
                    
                self._render_progress(completed, len(test_plan))
        
        return results

    def _run_tests_with_resource_scheduling(self, test_plan: List[Dict[str, Any]], max_nodes: int) -> List[Dict[str, Any]]:
        """Execute tests with resource-aware scheduling based on cluster sizes.
        
        Schedules tests to keep total nodes in use <= max_nodes.
        Example: max_nodes=4 allows running 1x4n OR 1x3n+1x1n OR 2x2n simultaneously.
        """
        results = []
        pending_tests = list(test_plan)  # Copy to avoid modifying original
        running_futures = {}  # {future: (test, nodes_used)}
        nodes_in_use = 0
        completed = 0
        
        # Sort tests by cluster size (largest first) for better packing
        pending_tests.sort(key=lambda t: t['parameters'].get('cluster_size', 1), reverse=True)
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(test_plan)) as executor:
            while pending_tests or running_futures:
                # Try to start new tests that fit in available resources
                while pending_tests:
                    test = pending_tests[0]
                    cluster_size = test['parameters'].get('cluster_size', 1)
                    
                    if nodes_in_use + cluster_size <= max_nodes:
                        # We have capacity, start this test
                        pending_tests.pop(0)
                        future = executor.submit(self._run_single_test, test)
                        running_futures[future] = (test, cluster_size)
                        nodes_in_use += cluster_size
                        self.logger.info(
                            f"Started {test['deployment_id']} ({cluster_size} nodes), "
                            f"using {nodes_in_use}/{max_nodes} nodes"
                        )
                    else:
                        # Not enough capacity, wait for a test to complete
                        break
                
                if not running_futures:
                    # All tests scheduled and completed
                    break
                
                # Wait for at least one test to complete
                done, _ = concurrent.futures.wait(
                    running_futures.keys(),
                    return_when=concurrent.futures.FIRST_COMPLETED
                )
                
                for future in done:
                    test, cluster_size = running_futures.pop(future)
                    nodes_in_use -= cluster_size
                    
                    result = future.result()
                    results.append(result)
                    self.notification_manager.record_result(result)
                    completed += 1
                    
                    status = 'PASS' if result['success'] else 'FAIL'
                    
                    # If test failed, try to clean up deployment to free resources
                    if not result['success']:
                        self.logger.warning(f"Test {result['deployment_id']} FAILED - attempting cleanup")
                        deploy_dir = Path(result.get('deployment_dir', ''))
                        if deploy_dir.exists():
                            try:
                                self._cleanup_failed_deployment(deploy_dir, result['deployment_id'])
                                self.logger.info(f"Cleanup completed for {result['deployment_id']}")
                            except Exception as cleanup_err:
                                self.logger.error(f"Cleanup failed for {result['deployment_id']}: {cleanup_err}")
                        
                        # Stop execution if --stop-on-error is set
                        if self.stop_on_error:
                            self.logger.error("Stopping execution due to test failure (--stop-on-error)")
                            # Cancel all pending tests
                            pending_tests.clear()
                            # Wait for running tests to complete
                            for remaining_future in running_futures.keys():
                                remaining_test, remaining_size = running_futures[remaining_future]
                                self.logger.info(f"Waiting for running test: {remaining_test['deployment_id']}")
                            # Let the loop finish running tests naturally
                    
                    self.logger.info(
                        f"Completed: {result['deployment_id']} - {status} ({result['duration']:.1f}s), "
                        f"freed {cluster_size} nodes, now using {nodes_in_use}/{max_nodes}"
                    )
                    
                    # Update progress
                    with self._progress_lock:
                        self._completed_tests = completed
                        self._current_deployment = None
                        self._current_step = None
                    
                    self._render_progress(completed, len(test_plan))
        
        return results

    def _cleanup_failed_deployment(self, deploy_dir: Path, deployment_id: str):
        """Clean up a failed deployment to free resources.
        
        Attempts to destroy the infrastructure and remove deployment directory.
        This prevents resource leaks when tests fail.
        """
        self.logger.info(f"Cleaning up failed deployment: {deployment_id}")
        
        # Try to run destroy command
        destroy_cmd = [
            './exasol', 'destroy',
            '--deployment-dir', str(deploy_dir),
            '--auto-approve'
        ]
        
        try:
            result = subprocess.run(
                destroy_cmd,
                capture_output=True,
                text=True,
                timeout=300,  # 5 minute timeout
                cwd=self.repo_root
            )
            
            if result.returncode != 0:
                self.logger.warning(
                    f"Destroy command returned {result.returncode}, "
                    f"resources may not be fully cleaned up"
                )
                # Continue anyway - partial cleanup is better than none
        
        except subprocess.TimeoutExpired:
            self.logger.error(f"Destroy command timed out for {deployment_id}")
        except Exception as e:
            self.logger.error(f"Destroy command failed for {deployment_id}: {e}")

    def _render_progress(self, completed: int, total: int, current_deployment: Optional[str] = None, current_step: Optional[str] = None):
        """Render an enhanced progress bar with deployment and step information."""
        if total == 0:
            return
        bar_length = 30
        fraction = min(1.0, completed / total)
        filled = int(bar_length * fraction)
        bar = '#' * filled + '-' * (bar_length - filled)
        
        # Build progress message
        message = f"Progress: [{bar}] {completed}/{total} tests completed"
        
        # Add current deployment info
        if current_deployment:
            # Truncate deployment ID if too long
            display_id = current_deployment[:20] + "..." if len(current_deployment) > 20 else current_deployment
            message += f" | {display_id}"
        
        # Add current step info
        if current_step:
            message += f" - {current_step}"
        
        with self._progress_lock:
            # Clear line completely, then write message
            # Use ANSI escape codes to clear the line
            print(f"\r\033[K{message}", end='', flush=True)
    
    def _log_deployment_step(self, deployment_id: str, step: str, status: str = "STARTED"):
        """Log deployment step to stdout with timestamp."""
        timestamp = datetime.now().strftime('%H:%M:%S')
        
        # Include status in the message if it's not the default
        if status != "STARTED":
            step_message = f"{timestamp} {deployment_id} {step} {status}"
        else:
            step_message = f"{timestamp} {deployment_id} {step}"
        
        with self._progress_lock:
            # Clear current progress line and print step
            print("\r" + " " * 100 + "\r", end='', flush=True)
            print(step_message, flush=True)
            
            # Re-render progress bar
            # Note: We'll track current deployment/step in the calling methods

    def _log_to_file(self, log_file: Path, message: str):
        """Append timestamped log entry to the per-test log file."""
        # Ensure parent directory exists
        log_file.parent.mkdir(parents=True, exist_ok=True)
        
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        with log_file.open('a', encoding='utf-8') as log_handle:
            log_handle.write(f"[{timestamp}] {message}\n")

    def _run_command(self, cmd: List[str], log_file: Path, cwd: Optional[Path] = None) -> subprocess.CompletedProcess:
        """Run a CLI command, capturing output in the test log."""
        cmd_str = ' '.join(cmd)
        self._log_to_file(log_file, f"Running command: {cmd_str}")
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(cwd or self.repo_root))
        if result.stdout:
            self._log_to_file(log_file, f"STDOUT:\n{result.stdout.strip()}")
        if result.stderr:
            self._log_to_file(log_file, f"STDERR:\n{result.stderr.strip()}")
        self._log_to_file(log_file, f"Command exited with {result.returncode}")
        return result





    def _save_results(self, results: List[Dict[str, Any]], total_time: float):
        """Save test results to JSON file."""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        results_file = self.results_dir / "results.json"

        # Extract unique providers from results
        providers = sorted(set(r.get('provider', 'unknown') for r in results))
        
        summary = {
            'timestamp': timestamp,
            'execution_dir': str(self.results_dir),
            'db_version': self.db_version or 'default',
            'provider': providers[0] if len(providers) == 1 else providers,
            'total_tests': len(results),
            'passed': sum(1 for r in results if r['success']),
            'failed': sum(1 for r in results if not r['success']),
            'total_time': total_time,
            'results': results
        }
        if self.resource_plan_metrics:
            summary['resource_plan'] = self.resource_plan_metrics
        notification_artifact = self.notification_manager.flush_to_disk()
        if notification_artifact:
            summary['notifications'] = notification_artifact

        with open(results_file, 'w', encoding='utf-8') as f:
            json.dump(summary, f, indent=2, default=str)

        html_filename = "results.html"
        self.html_report_generator.generate(summary, html_filename)

        self.logger.info(f"Results saved to {results_file}")
        print(f"\nResults saved to: {self.results_dir}")
        print(f"  - results.json")
        print(f"  - results.html")

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
        if self.resource_plan_metrics:
            plan = self.resource_plan_metrics
            print(
                f"Planned Instances: {plan.get('total_instances', 0)} | "
                f"Max Cluster Size: {plan.get('max_cluster_size', 0)}"
            )

        if failed > 0:
            print(f"\n{'='*50}")
            print("FAILED TESTS:")
            print(f"{'='*50}")
            for result in results:
                if not result['success']:
                    print(f"- {result['deployment_id']}: {result.get('error', 'Unknown error')}")

    def _run_single_test(self, test_case: Dict[str, Any]) -> Dict[str, Any]:
        """Run a single test case using the workflow engine."""
        deployment_id = test_case['deployment_id']
        suite_name = test_case['suite']
        provider = test_case['provider']
        workflow_steps = test_case.get('workflow', [])

        # Determine run number for this suite
        run_number = self.suite_run_counts.get(suite_name, 0) + 1
        self.suite_run_counts[suite_name] = run_number
        
        # Create log file and deployment directory with matching names
        if run_number == 1:
            base_name = suite_name
        else:
            base_name = f"{suite_name}-run{run_number}"
        
        log_file = self.results_dir / f"{base_name}.log"
        self._log_to_file(log_file, f"Starting workflow test {suite_name} ({provider})")
        
        # Update progress tracking
        with self._progress_lock:
            self._current_deployment = suite_name
            self._current_step = "initializing"
        
        self._log_deployment_step(suite_name, "STARTED", "workflow")

        result = {
            'deployment_id': deployment_id,  # Keep for backward compatibility
            'suite': suite_name,
            'provider': provider,
            'test_type': 'workflow',
            'run_number': run_number,
            'db_version': self.db_version or 'default',
            'success': False,
            'duration': 0,
            'error': None,
            'logs': [],
            'steps': [],  # Workflow step results
            'log_file': str(log_file),
            'config_path': test_case.get('config_path', str(self.config_path)),
            'parameters': test_case.get('parameters', {}),
            'workflow': workflow_steps,
            'sut_description': test_case.get('sut_description', '')
        }

        start_time = time.time()

        # Create deployment directory with same name as log file (without .log extension)
        deploy_dir = self.work_dir / base_name
        deploy_dir.mkdir(exist_ok=True)
        result['deployment_dir'] = str(deploy_dir)

        emergency_handler = self._initialize_emergency_handler(deployment_id, deploy_dir)
        resource_tracker = self._initialize_resource_tracker(deploy_dir, emergency_handler)

        try:
            params = test_case['parameters']
            
            # Import workflow engine (relative import within package)
            import sys
            from pathlib import Path
            # Add tests directory to path if not already there
            tests_dir = Path(__file__).resolve().parent.parent
            if str(tests_dir) not in sys.path:
                sys.path.insert(0, str(tests_dir))
            
            from e2e.workflow_engine import WorkflowExecutor, StepStatus
            
            # Create log callback for workflow executor
            def log_callback(msg: str):
                self._log_to_file(log_file, msg)
                # Extract step name from message if possible
                if msg.startswith('STEP:'):
                    step_name = msg[6:].strip()[:30]
                    with self._progress_lock:
                        self._current_step = step_name
                    self._render_progress(
                        self._completed_tests,
                        self._total_tests,
                        suite_name,
                        step_name
                    )

            # Resolve database version with fallback support
            suite_db_version = test_case.get('db_version')
            resolved_db_version = self._resolve_db_version(suite_db_version)

            # Create workflow executor
            executor = WorkflowExecutor(
                deploy_dir=deploy_dir,
                provider=provider,
                logger=self.logger,
                log_callback=log_callback,
                db_version=resolved_db_version
            )

            # Execute workflow
            self._log_to_file(log_file, f"Workflow has {len(workflow_steps)} steps")

            step_results = executor.execute_workflow(workflow_steps, params)

            # Convert step results to serializable format
            for step_result in step_results:
                step_dict = {
                    'step': step_result.step_type,
                    'description': step_result.description,
                    'status': step_result.status.value,
                    'duration': step_result.duration,
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'error': step_result.error,
                    'result': step_result.result,
                    'validation_results': step_result.validation_results,
                    'target_node': step_result.target_node,
                    'method': step_result.method
                }
                result['steps'].append(step_dict)

                # Log each step completion
                status_symbol = "✓" if step_result.status == StepStatus.COMPLETED else "✗"
                status_msg = f"{status_symbol} Step: {step_result.step_type}"
                if step_result.description:
                    status_msg += f" ({step_result.description})"
                status_msg += f" - {step_result.status.value} ({step_result.duration:.1f}s)"
                
                self._log_to_file(log_file, status_msg)
                self._log_deployment_step(suite_name, step_result.step_type, step_result.status.value)

            # Determine overall success
            failed_steps = [s for s in step_results if s.status == StepStatus.FAILED]
            result['success'] = len(failed_steps) == 0

            if failed_steps:
                result['error'] = f"{len(failed_steps)} workflow step(s) failed"
                for failed in failed_steps:
                    error_msg = f"Failed: {failed.step_type}"
                    if failed.description:
                        error_msg += f" ({failed.description})"
                    error_msg += f" - {failed.error}"
                    result['logs'].append(error_msg)
                    self._log_to_file(log_file, error_msg)

        except Exception as e:
            result['error'] = str(e)
            result['logs'].append(f"Workflow execution error: {e}")
            result['steps'].append({
                'step': self._current_step or 'unknown',
                'status': 'failed',
                'duration': 0,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'error': str(e)
            })
            self._log_to_file(log_file, f"Workflow test {suite_name} failed: {e}")
            if emergency_handler:
                try:
                    emergency_handler.emergency_cleanup(deployment_id)
                except Exception as cleanup_error:
                    self._log_to_file(log_file, f"Emergency cleanup error: {cleanup_error}")

        finally:
            result['duration'] = time.time() - start_time

            # Note: Cleanup (destroy) should be part of the workflow steps
            # No automatic cleanup here - workflow defines all steps including destroy
            
            if emergency_handler:
                emergency_handler.stop_timeout_monitoring()
                result['emergency_summary'] = self._get_emergency_summary(emergency_handler)
            else:
                result['emergency_summary'] = None

            # Log completion
            status = "COMPLETED" if result['success'] else "FAILED"
            self._log_deployment_step(suite_name, status, f"duration: {result['duration']:.1f}s")
            
            # Clear current deployment from progress tracking
            with self._progress_lock:
                self._current_deployment = None
                self._current_step = None

        return result

    def _init_deployment(self, deploy_dir: Path, provider: str, params: Dict[str, Any], log_file: Path):
        """Initialize deployment using exasol CLI."""
        cmd = [
            './exasol', 'init',
            '--cloud-provider', provider,
            '--deployment-dir', str(deploy_dir)
        ]

        # Add supported parameters as CLI flags
        param_flag_map = {
            'cluster_size': '--cluster-size',
            'instance_type': '--instance-type',
            'data_volumes_per_node': '--data-volumes-per-node',
            'data_volume_size': '--data-volume-size',
            'root_volume_size': '--root-volume-size',
            'db_version': '--db-version',
            'allowed_cidr': '--allowed-cidr',
        }
        for key, flag in param_flag_map.items():
            if key in params:
                cmd.extend([flag, str(params[key])])

        if params.get('enable_spot_instances'):
            provider_flag = {
                'aws': '--aws-spot-instance',
                'azure': '--azure-spot-instance',
                'gcp': '--gcp-spot-instance'
            }.get(provider.lower())
            if provider_flag:
                cmd.append(provider_flag)

        result = self._run_command(cmd, log_file, cwd=self.repo_root)
        if result.returncode != 0:
            raise RuntimeError(f"Init failed: {result.stderr}")

    def _deploy(self, deploy_dir: Path, params: Dict[str, Any], log_file: Path):
        """Deploy using exasol CLI."""
        cmd = ['./exasol', 'deploy', '--deployment-dir', str(deploy_dir)]

        result = self._run_command(cmd, log_file, cwd=self.repo_root)
        if result.returncode != 0:
            raise RuntimeError(f"Deploy failed: {result.stderr}")

    def _validate_deployment(
        self,
        deploy_dir: Path,
        params: Dict[str, Any],
        provider: str,
        log_file: Path,
        resource_tracker: Optional[Any] = None
    ) -> Dict[str, Any]:
        """Validate deployment outcomes."""
        validation = {
            'success': True,
            'checks': []
        }

        # Log validation steps
        deployment_id = deploy_dir.name
        with self._progress_lock:
            self._current_step = "checking terraform state"
        self._log_deployment_step(deployment_id, "checking terraform state", "in progress")
        self._render_progress(self._completed_tests, self._total_tests, deployment_id, "checking state")
        
        tf_state = self._load_terraform_state(deploy_dir, log_file, validation)
        if not tf_state:
            validation['success'] = False
            self._log_deployment_step(deployment_id, "checking terraform state", "failed")
        else:
            self._register_resources_from_state(resource_tracker, tf_state, provider, deploy_dir.name)
            self._log_deployment_step(deployment_id, "checking terraform state", "completed")

        # Check terraform outputs
        with self._progress_lock:
            self._current_step = "checking outputs"
        self._log_deployment_step(deployment_id, "checking outputs", "in progress")
        self._render_progress(self._completed_tests, self._total_tests, deployment_id, "checking outputs")
        
        outputs_file = deploy_dir / 'outputs.tf'
        if outputs_file.exists():
            validation['checks'].append({'check': 'outputs_file_exists', 'status': 'pass'})
            self._log_deployment_step(deployment_id, "checking outputs", "completed")
        else:
            validation['checks'].append({'check': 'outputs_file_exists', 'status': 'fail'})
            validation['success'] = False
            self._log_deployment_step(deployment_id, "checking outputs", "failed")

        self._validate_tfvars_alignment(params, validation, deploy_dir)

        # Check inventory file (generated by terraform)
        with self._progress_lock:
            self._current_step = "checking inventory"
        self._log_deployment_step(deployment_id, "checking inventory", "in progress")
        self._render_progress(self._completed_tests, self._total_tests, deployment_id, "checking inventory")
        
        inventory_file = deploy_dir / 'inventory.ini'
        inventory_data = {'sections': {}, 'hosts': []}  # Initialize with default value
        if inventory_file.exists():
            validation['checks'].append({'check': 'inventory_file_exists', 'status': 'pass'})
            self._log_deployment_step(deployment_id, "checking inventory", "completed")

            inventory_data = self._parse_inventory(inventory_file, validation)
            node_entries = inventory_data.get('sections', {}).get('exasol_nodes', [])
            expected_cluster = params.get('cluster_size')
            actual_cluster = len(node_entries)
            if expected_cluster is not None:
                check_status = 'pass' if actual_cluster == expected_cluster else 'fail'
                validation['checks'].append({
                    'check': 'cluster_size_matches',
                    'expected': expected_cluster,
                    'actual': actual_cluster,
                    'status': check_status
                })
                if check_status == 'fail':
                    validation['success'] = False

            # Log detailed validation steps
            with self._progress_lock:
                self._current_step = "validating volumes"
            self._log_deployment_step(deployment_id, "validating volumes", "in progress")
            self._validate_volume_counts(params, inventory_data, validation)
            self._log_deployment_step(deployment_id, "validating volumes", "completed")
            
            with self._progress_lock:
                self._current_step = "validating network"
            self._log_deployment_step(deployment_id, "validating network", "in progress")
            self._validate_network_endpoints(node_entries, validation)
            self._log_deployment_step(deployment_id, "validating network", "completed")
            
            with self._progress_lock:
                self._current_step = "validating ports"
            self._log_deployment_step(deployment_id, "validating ports", "in progress")
            self._validate_admin_and_db_ports(node_entries, validation, log_file)
            self._log_deployment_step(deployment_id, "validating ports", "completed")
            
            with self._progress_lock:
                self._current_step = "validating ssh"
            self._log_deployment_step(deployment_id, "validating ssh", "in progress")
            self._validate_ssh_access(node_entries, deploy_dir, validation, log_file)
            self._log_deployment_step(deployment_id, "validating ssh", "completed")
        else:
            validation['checks'].append({'check': 'inventory_file_exists', 'status': 'fail'})
            validation['success'] = False
            self._log_deployment_step(deployment_id, "checking inventory", "failed")

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

# Verify infrastructure settings via terraform state
        self._validate_instance_configuration(provider, params, tf_state, validation)
        self._validate_disk_configuration(provider, params, tf_state, validation)

        # Perform live system validation via SSH if available
        if SSH_VALIDATION_AVAILABLE and inventory_file.exists():
            try:
                self._perform_ssh_validation(deploy_dir, params, inventory_data, validation, log_file)
            except Exception as e:
                self.logger.warning(f"SSH validation failed: {e}")
                validation['checks'].append({
                    'check': 'ssh_validation',
                    'status': 'fail',
                    'error': str(e)
                })

        return validation

    def _perform_ssh_validation(self, deploy_dir: Path, params: Dict[str, Any], inventory_data: Dict[str, Any], validation: Dict[str, Any], log_file: Path):
        """Perform live system validation via SSH."""
        deployment_id = deploy_dir.name
        try:
            # Initialize SSH validator
            # Re-import to ensure we have the correct reference
            from tests.e2e.ssh_validator import SSHValidator
            ssh_validator = SSHValidator(deploy_dir, dry_run=not self.enable_live_validation)
            
            # Perform symlink validation
            with self._progress_lock:
                self._current_step = "checking symlinks"
            self._log_deployment_step(deployment_id, "checking symlinks", "in progress")
            self._render_progress(self._completed_tests, self._total_tests, deployment_id, "checking symlinks")
            
            symlink_results = ssh_validator.validate_symlinks()
            symlink_passed = sum(1 for r in symlink_results if r.success)
            symlink_total = len(symlink_results)
            validation['checks'].append({
                'check': 'ssh_symlink_validation',
                'status': 'pass' if symlink_passed == symlink_total else 'fail',
                'passed': symlink_passed,
                'total': symlink_total
            })
            self._log_deployment_step(deployment_id, "checking symlinks", "completed")
            
            # Perform service validation
            with self._progress_lock:
                self._current_step = "checking services"
            self._log_deployment_step(deployment_id, "checking services", "in progress")
            self._render_progress(self._completed_tests, self._total_tests, deployment_id, "checking services")
            
            service_results = ssh_validator.validate_services()
            service_passed = sum(1 for r in service_results if r.success)
            service_total = len(service_results)
            validation['checks'].append({
                'check': 'ssh_service_validation',
                'status': 'pass' if service_passed == service_total else 'fail',
                'passed': service_passed,
                'total': service_total
            })
            self._log_deployment_step(deployment_id, "checking services", "completed")
            
            # Perform database installation validation
            with self._progress_lock:
                self._current_step = "checking database"
            self._log_deployment_step(deployment_id, "checking database", "in progress")
            self._render_progress(self._completed_tests, self._total_tests, deployment_id, "checking database")
            
            db_results = ssh_validator.validate_database_installation()
            db_passed = sum(1 for r in db_results if r.success)
            db_total = len(db_results)
            validation['checks'].append({
                'check': 'ssh_database_validation',
                'status': 'pass' if db_passed == db_total else 'fail',
                'passed': db_passed,
                'total': db_total
            })
            self._log_deployment_step(deployment_id, "checking database", "completed")
            
            # Perform system resources validation
            with self._progress_lock:
                self._current_step = "checking resources"
            self._log_deployment_step(deployment_id, "checking resources", "in progress")
            self._render_progress(self._completed_tests, self._total_tests, deployment_id, "checking resources")
            
            resource_results = ssh_validator.validate_system_resources()
            resource_passed = sum(1 for r in resource_results if r.success)
            resource_total = len(resource_results)
            validation['checks'].append({
                'check': 'ssh_system_resources_validation',
                'status': 'pass' if resource_passed == resource_total else 'fail',
                'passed': resource_passed,
                'total': resource_total
            })
            self._log_deployment_step(deployment_id, "checking resources", "completed")
            
            # Update overall success based on SSH validation
            ssh_checks = [check for check in validation['checks'] if check['check'].startswith('ssh_')]
            if ssh_checks and not all(check['status'] == 'pass' for check in ssh_checks):
                validation['success'] = False
                
        except Exception as e:
            self.logger.warning(f"SSH validation failed: {e}")
            validation['checks'].append({
                'check': 'ssh_validation',
                'status': 'fail',
                'error': str(e)
            })

    def _cleanup_deployment(self, deploy_dir: Path, provider: str, log_file: Path, keep_artifacts: bool = False, suite_name: Optional[str] = None) -> Optional[Path]:
        """Cleanup deployment resources."""
        retained_path: Optional[Path] = None
        if keep_artifacts and deploy_dir.exists():
            # Use suite name for retained directory if provided, otherwise deployment dir name\n            dir_name = suite_name if suite_name else deploy_dir.name
            retained_path = self.retained_root / dir_name
            if retained_path.exists():
                shutil.rmtree(retained_path)
            shutil.copytree(str(deploy_dir), str(retained_path))
            self._log_to_file(log_file, f"Retained deployment directory for investigation: {retained_path}")

        if deploy_dir.exists():
            cmd = ['./exasol', 'destroy', '--deployment-dir', str(deploy_dir), '--auto-approve']

            result = self._run_command(cmd, log_file, cwd=self.repo_root)
            if result.returncode != 0:
                self._log_to_file(log_file, f"Warning: Cleanup failed for {deploy_dir}: {result.stderr}")

            if not keep_artifacts:
                shutil.rmtree(deploy_dir, ignore_errors=True)

        return retained_path

    def _parse_inventory(self, inventory_file: Path, validation: Dict[str, Any]) -> Dict[str, Any]:
        inventory_data = {'hosts': [], 'sections': {}}
        try:
            with open(inventory_file, 'r', encoding='utf-8') as f:
                current_section = None
                for line in f:
                    stripped = line.strip()
                    if not stripped or stripped.startswith('#'):
                        continue
                    if stripped.startswith('[') and stripped.endswith(']'):
                        current_section = stripped[1:-1]
                        inventory_data['sections'].setdefault(current_section, [])
                        continue
                    parts = stripped.split()
                    host_name = parts[0]
                    vars_dict = {}
                    for token in parts[1:]:
                        if '=' in token:
                            key, value = token.split('=', 1)
                            vars_dict[key] = value.strip().strip("'\"")
                    entry = {
                        'name': host_name,
                        'vars': vars_dict,
                        'section': current_section,
                        'ip': vars_dict.get('ansible_host', host_name)
                    }
                    inventory_data['hosts'].append(entry)
                    if current_section:
                        inventory_data['sections'].setdefault(current_section, []).append(entry)
        except Exception as exc:
            validation['checks'].append({
                'check': 'inventory_parsing',
                'status': 'fail',
                'error': str(exc)
            })
            validation['success'] = False
        return inventory_data

    def _parse_tfvars(self, deploy_dir: Path) -> Optional[Dict[str, Any]]:
        tfvars_path = deploy_dir / 'variables.auto.tfvars'
        if not tfvars_path.exists():
            return None
        data: Dict[str, Any] = {}
        try:
            with open(tfvars_path, 'r', encoding='utf-8') as tf_file:
                for raw_line in tf_file:
                    line = raw_line.strip()
                    if not line or line.startswith('#') or '=' not in line:
                        continue
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip().rstrip(',')
                    if value.startswith('"') and value.endswith('"'):
                        data[key] = value.strip('"')
                    elif value in ('true', 'false'):
                        data[key] = value == 'true'
                    else:
                        try:
                            data[key] = int(value)
                        except ValueError:
                            try:
                                data[key] = float(value)
                            except ValueError:
                                data[key] = value
        except Exception as exc:
            self.logger.warning(f"Failed to parse tfvars file: {exc}")
            return None
        return data

    def _validate_tfvars_alignment(self, params: Dict[str, Any], validation: Dict[str, Any], deploy_dir: Path):
        tfvars = self._parse_tfvars(deploy_dir)
        if tfvars is None:
            validation['checks'].append({'check': 'tfvars_exists', 'status': 'fail'})
            validation['success'] = False
            return

        validation['checks'].append({'check': 'tfvars_exists', 'status': 'pass'})

        mapping = {
            'cluster_size': 'node_count',
            'instance_type': 'instance_type',
            'data_volumes_per_node': 'data_volumes_per_node',
            'data_volume_size': 'data_volume_size',
            'root_volume_size': 'root_volume_size',
            'allowed_cidr': 'allowed_cidr',
            'enable_spot_instances': 'enable_spot_instances'
        }

        for param_key, tfvar_key in mapping.items():
            if param_key not in params:
                continue
            expected = params[param_key]
            actual = tfvars.get(tfvar_key)
            status = 'pass' if actual == expected else 'fail'
            validation['checks'].append({
                'check': f'{param_key}_tfvars_match',
                'expected': expected,
                'actual': actual,
                'status': status
            })
            if status == 'fail':
                validation['success'] = False

    def _load_terraform_state(self, deploy_dir: Path, log_file: Path, validation: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        candidates = [
            deploy_dir / 'terraform.tfstate',
            deploy_dir / '.terraform' / 'terraform.tfstate'
        ]
        for state_path in candidates:
            if state_path.exists():
                try:
                    with open(state_path, 'r', encoding='utf-8') as f:
                        state = json.load(f)
                    validation['checks'].append({
                        'check': 'terraform_state_exists',
                        'status': 'pass',
                        'path': str(state_path)
                    })
                    return state
                except Exception as exc:
                    validation['checks'].append({
                        'check': 'terraform_state_parse',
                        'status': 'fail',
                        'error': str(exc)
                    })
                    self._log_to_file(log_file, f"Failed to parse terraform state: {exc}")
                    return None
        validation['checks'].append({'check': 'terraform_state_exists', 'status': 'fail'})
        self._log_to_file(log_file, "Terraform state file missing.")
        return None

    def _collect_resources(self, tf_state: Dict[str, Any], resource_type: str) -> List[Dict[str, Any]]:
        resources = []
        for resource in tf_state.get('resources', []):
            if resource.get('type') == resource_type:
                for instance in resource.get('instances', []):
                    resources.append(instance.get('attributes', {}))
        return resources

    def _validate_instance_configuration(self, provider: str, params: Dict[str, Any], tf_state: Optional[Dict[str, Any]], validation: Dict[str, Any]):
        if not tf_state:
            return
        provider_map = {
            'aws': ('aws_instance', 'instance_type'),
            'azure': ('azurerm_linux_virtual_machine', 'size'),
            'gcp': ('google_compute_instance', 'machine_type'),
            'digitalocean': ('digitalocean_droplet', 'size'),
            'hetzner': ('hcloud_server', 'server_type')
        }
        config = provider_map.get(provider)
        if not config:
            return

        resource_type, attr_name = config
        resources = self._collect_resources(tf_state, resource_type)
        if not resources:
            validation['checks'].append({
                'check': 'instance_resources_found',
                'provider': provider,
                'status': 'fail'
            })
            validation['success'] = False
            return

        expected_type = params.get('instance_type')
        mismatches = [
            r.get(attr_name) for r in resources
            if expected_type is not None and r.get(attr_name) != expected_type
        ]
        status = 'pass' if not mismatches else 'fail'
        validation['checks'].append({
            'check': 'instance_type_matches',
            'expected': expected_type,
            'status': status
        })
        if status == 'fail':
            validation['success'] = False

    def _validate_disk_configuration(self, provider: str, params: Dict[str, Any], tf_state: Optional[Dict[str, Any]], validation: Dict[str, Any]):
        if not tf_state:
            return

        disk_map = {
            'aws': ('aws_ebs_volume', 'size'),
            'azure': ('azurerm_managed_disk', 'disk_size_gb'),
            'gcp': ('google_compute_disk', 'size'),
            'digitalocean': ('digitalocean_volume', 'size'),
            'hetzner': ('hcloud_volume', 'size')
        }
        config = disk_map.get(provider)
        if not config:
            return

        resource_type, attr_name = config
        resources = self._collect_resources(tf_state, resource_type)
        expected_per_node = params.get('data_volumes_per_node')
        cluster_size = params.get('cluster_size')
        expected_total = (expected_per_node or 0) * (cluster_size or 0)

        status = 'pass'
        if expected_total and len(resources) != expected_total:
            status = 'fail'
        validation['checks'].append({
            'check': 'data_volume_count',
            'expected': expected_total,
            'actual': len(resources),
            'status': status
        })
        if status == 'fail':
            validation['success'] = False

        expected_size = params.get('data_volume_size')
        if expected_size is None:
            return

        mismatched = [
            r.get(attr_name) for r in resources if r.get(attr_name) != expected_size
        ]
        size_status = 'pass' if not mismatched else 'fail'
        validation['checks'].append({
            'check': 'data_volume_size_matches',
            'expected': expected_size,
            'status': size_status
        })
        if size_status == 'fail':
            validation['success'] = False

    def _validate_volume_counts(self, params: Dict[str, Any], inventory_data: Dict[str, Any], validation: Dict[str, Any]):
        expected_per_node = params.get('data_volumes_per_node')
        if expected_per_node is None:
            return
        nodes = inventory_data.get('sections', {}).get('exasol_nodes', [])
        for entry in nodes:
            data_ids = entry['vars'].get('data_volume_ids')
            volumes = []
            if data_ids:
                cleaned = data_ids.strip("'\"")
                try:
                    volumes = json.loads(cleaned)
                except json.JSONDecodeError:
                    volumes = cleaned.split(',')
            status = 'pass' if len(volumes) == expected_per_node else 'fail'
            validation['checks'].append({
                'check': 'data_volumes_per_node',
                'host': entry['name'],
                'expected': expected_per_node,
                'actual': len(volumes),
                'status': status
            })
            if status == 'fail':
                validation['success'] = False

    def _validate_network_endpoints(self, node_entries: List[Dict[str, Any]], validation: Dict[str, Any]):
        if not node_entries:
            validation['checks'].append({
                'check': 'inventory_nodes_present',
                'status': 'fail'
            })
            validation['success'] = False
            return
        for entry in node_entries:
            ip = entry.get('ip')
            status = 'pass' if ip else 'fail'
            validation['checks'].append({
                'check': 'node_has_ip',
                'host': entry['name'],
                'status': status
            })
            if status == 'fail':
                validation['success'] = False

    def _validate_admin_and_db_ports(self, node_entries: List[Dict[str, Any]], validation: Dict[str, Any], log_file: Path):
        for entry in node_entries:
            ip = entry.get('ip')
            if not ip:
                continue
            admin_ok = self._check_https_endpoint(ip, 8443, log_file)
            validation['checks'].append({
                'check': 'admin_ui_response',
                'host': entry['name'],
                'status': 'pass' if admin_ok else 'fail'
            })
            if not admin_ok:
                validation['success'] = False

            db_ok = self._check_tcp_port(ip, 8563, log_file)
            validation['checks'].append({
                'check': 'db_port_response',
                'host': entry['name'],
                'status': 'pass' if db_ok else 'fail'
            })
            if not db_ok:
                validation['success'] = False

    def _validate_ssh_access(self, node_entries: List[Dict[str, Any]], deploy_dir: Path, validation: Dict[str, Any], log_file: Path):
        ssh_config = deploy_dir / 'ssh_config'
        if not ssh_config.exists():
            validation['checks'].append({'check': 'ssh_config_exists', 'status': 'fail'})
            validation['success'] = False
            return

        for entry in node_entries:
            host_alias = entry['name']
            base_cmd = [
                'ssh', '-F', str(ssh_config),
                '-o', 'BatchMode=yes',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'ConnectTimeout=30'
            ]
            cmd = base_cmd + [host_alias, 'true']
            result = self._run_command(cmd, log_file, cwd=deploy_dir)
            status = 'pass' if result.returncode == 0 else 'fail'
            validation['checks'].append({
                'check': 'instance_ssh',
                'host': host_alias,
                'status': status
            })
            if status == 'fail':
                validation['success'] = False

            cos_alias = f"{host_alias}-cos"
            cos_cmd = base_cmd + [cos_alias, 'true']
            cos_result = self._run_command(cos_cmd, log_file, cwd=deploy_dir)
            cos_status = 'pass' if cos_result.returncode == 0 else 'fail'
            validation['checks'].append({
                'check': 'cos_ssh',
                'host': cos_alias,
                'status': cos_status
            })
            if cos_status == 'fail':
                validation['success'] = False

    def _initialize_emergency_handler(self, deployment_id: str, deploy_dir: Path):
        if not EMERGENCY_TOOLING_AVAILABLE or EmergencyHandler is None:
            return None
        timeout_minutes = self.quota_monitor.limits.get('deployment_timeout_minutes', 45)
        handler = EmergencyHandler(
            deploy_dir,
            timeout_minutes=timeout_minutes,
            dry_run=not self.live_mode
        )
        handler.start_timeout_monitoring(deployment_id)
        return handler

    def _initialize_resource_tracker(self, deploy_dir: Path, emergency_handler: Optional[Any]):
        if emergency_handler:
            return emergency_handler.resource_tracker
        if not EMERGENCY_TOOLING_AVAILABLE or not ResourceTracker:
            return None
        return ResourceTracker(deploy_dir, dry_run=not self.live_mode)

    def _collect_resource_tracking_summary(self, resource_tracker: Optional[Any], deployment_id: str):
        if not resource_tracker:
            return None
        try:
            resources = resource_tracker.get_resources_by_deployment(deployment_id)
        except AttributeError:
            resources = list(getattr(resource_tracker, 'resources', {}).values())
        try:
            estimated_cost = resource_tracker.estimate_total_cost(deployment_id)
        except Exception:
            estimated_cost = 0.0
        return {
            'resource_count': len(resources) if resources else 0,
            'estimated_cost': estimated_cost
        }

    def _register_resources_from_state(
        self,
        resource_tracker: Optional[Any],
        tf_state: Dict[str, Any],
        provider: str,
        deployment_id: str
    ):
        if not (resource_tracker and EMERGENCY_TOOLING_AVAILABLE and ResourceInfo):
            return
        current_time = datetime.utcnow()
        for resource in tf_state.get('resources', []):
            resource_type = resource.get('type')
            for instance in resource.get('instances', []):
                attributes = instance.get('attributes', {})
                resource_id = (
                    attributes.get('id')
                    or attributes.get('identifier')
                    or attributes.get('name')
                )
                if not resource_id:
                    continue
                estimated_cost = self._estimate_resource_cost(resource_type, attributes)
                info = ResourceInfo(
                    resource_id=str(resource_id),
                    resource_type=resource_type,
                    provider=provider,
                    deployment_id=deployment_id,
                    creation_time=current_time,
                    status=str(attributes.get('status', 'unknown')),
                    estimated_cost=estimated_cost
                )
                resource_tracker.register_resource(info)

    def _estimate_resource_cost(self, resource_type: Optional[str], attributes: Dict[str, Any]) -> float:
        if not resource_type:
            return 0.5
        resource_type = resource_type.lower()
        size_value = 0.0
        for key in ('size', 'disk_size_gb', 'volume_size'):
            if key in attributes:
                try:
                    size_value = float(attributes[key])
                except (TypeError, ValueError):
                    size_value = 0.0
                break
        base_costs = {
            'aws_instance': 1.5,
            'aws_ebs_volume': 0.06,
            'azurerm_linux_virtual_machine': 1.3,
            'azurerm_managed_disk': 0.05,
            'google_compute_instance': 1.2,
            'google_compute_disk': 0.05,
            'digitalocean_droplet': 0.8,
            'digitalocean_volume': 0.04,
            'hcloud_server': 0.7,
            'hcloud_volume': 0.03
        }
        base_cost = base_costs.get(resource_type, 0.5)
        if 'volume' in resource_type or 'disk' in resource_type:
            return base_cost * max(size_value, 1)
        return base_cost

    def _get_emergency_summary(self, emergency_handler: Optional[Any]):
        if not emergency_handler:
            return None
        summary = emergency_handler.get_cleanup_summary()
        summary['timeout_triggered'] = emergency_handler.timeout_triggered
        try:
            summary['leak_report'] = emergency_handler.check_resource_leaks()
        except Exception:
            summary['leak_report'] = None
        return summary

    def _check_https_endpoint(self, host: str, port: int, log_file: Path) -> bool:
        connection: Optional[http.client.HTTPSConnection] = None
        try:
            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            connection = http.client.HTTPSConnection(host, port, timeout=15, context=context)
            connection.request('GET', '/')
            response = connection.getresponse()
            success = response.status < 500
            return success
        except Exception as exc:
            self._log_to_file(log_file, f"HTTPS check failed for {host}:{port} - {exc}")
            return False
        finally:
            if connection:
                try:
                    connection.close()
                except Exception:
                    pass

    def _cleanup(self):
        """Clean up resources on exit."""
        # Close file handler to prevent ResourceWarning
        if hasattr(self, 'file_handler'):
            self.file_handler.close()
        
        # Note: work_dir is now under results_dir/deployments and should be retained
        # Individual deployment cleanup is handled by _cleanup_deployment()

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit with cleanup."""
        self._cleanup()
        return False  # Don't suppress exceptions

    def _check_tcp_port(self, host: str, port: int, log_file: Path, timeout: int = 10) -> bool:
        try:
            with socket.create_connection((host, port), timeout=timeout):
                return True
        except OSError as exc:
            self._log_to_file(log_file, f"TCP check failed for {host}:{port} - {exc}")
            return False


def main():
    parser = argparse.ArgumentParser(description='Exasol E2E Test Framework')
    parser.add_argument('action', choices=['plan', 'run'], help='Action to perform')
    parser.add_argument('--config', required=True, help='Path to test configuration file')
    parser.add_argument('--results-dir', default=None, help='Path to results directory (default: auto-generated e2e-{timestamp})')
    parser.add_argument('--dry-run', action='store_true', help='Generate plan without executing')
    parser.add_argument('--parallel', type=int, default=0, help='Maximum parallel executions (0=auto)')
    parser.add_argument('--stop-on-error', action='store_true', help='Stop execution on first test failure (for debugging)')
    parser.add_argument('--providers', help='Comma separated list of providers to include (e.g. aws,gcp)')
    parser.add_argument('--tests', help='Comma separated deployment IDs to execute')
    parser.add_argument('--db-version', help='Database version to use (overrides config, e.g. 8.0.0-x86_64)')

    args = parser.parse_args()

    try:
        framework = E2ETestFramework(
            args.config,
            Path(args.results_dir) if args.results_dir else None,
            db_version=args.db_version,
            stop_on_error=args.stop_on_error
        )
    except ValueError as e:
        # Configuration validation failed - error already printed to stderr
        sys.exit(1)

    provider_filter = (
        {p.strip().lower() for p in args.providers.split(',') if p.strip()}
        if args.providers else None
    )
    tests_filter = (
        {t.strip() for t in args.tests.split(',') if t.strip()}
        if args.tests else None
    )

    if args.action == 'plan':
        framework.generate_test_plan(dry_run=True, providers=provider_filter, only_tests=tests_filter)
    elif args.action == 'run':
        test_plan = framework.generate_test_plan(
            dry_run=args.dry_run,
            providers=provider_filter,
            only_tests=tests_filter
        )
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
