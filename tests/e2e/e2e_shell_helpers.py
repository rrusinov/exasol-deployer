#!/usr/bin/env python3
"""
Helper functions for run_e2e.sh shell script.
Provides utilities for listing tests, resolving test IDs, and analyzing results.
"""

import json
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

# Add repository root to Python path
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
sys.path.insert(0, str(REPO_ROOT))


def print_failures(results_file: str) -> None:
    """Print failed test information as JSON."""
    with open(results_file, 'r', encoding='utf-8') as fh:
        data = json.load(fh)

    failed = []
    for result in data.get('results', []):
        if not result.get('success'):
            failed.append({
                'id': result.get('deployment_id'),
                'suite': result.get('suite'),
                'provider': result.get('provider'),
                'log_file': result.get('log_file'),
                'retained_dir': result.get('retained_deployment_dir')
            })

    print(json.dumps(failed))


def tail_failed_logs(failures_json: str) -> None:
    """Display tail of log files for failed tests."""
    failures = json.loads(failures_json)
    for entry in failures:
        identifier = entry["id"]
        provider = entry.get("provider")
        suite = entry.get("suite")
        log_path = entry.get("log_file")
        retained_dir = entry.get("retained_dir")
        
        header = f"[{identifier}] provider={provider} suite={suite}"
        print("=" * len(header))
        print(header)
        print("=" * len(header))
        
        if log_path and os.path.isfile(log_path):
            print(f"-- Last 100 log lines from {log_path} --")
            subprocess.run(["tail", "-n", "100", log_path], check=False)
        else:
            print(f"No log file found at {log_path}")
        
        if retained_dir:
            print(f"Retained deployment directory: {retained_dir}")
        else:
            print("Deployment directory was cleaned up.")
        print()


def list_tests_for_configs(results_dir: str, provider_filter: str, configs: list) -> None:
    """List all available tests grouped by provider."""
    from tests.e2e.e2e_framework import E2ETestFramework
    
    results_dir_path = Path(results_dir) if results_dir else None
    provider_filter = provider_filter.lower() if provider_filter else ''

    if not configs:
        print("No e2e configuration files found.", file=sys.stderr)
        sys.exit(1)

    tests_by_provider = defaultdict(list)
    for cfg in configs:
        framework = E2ETestFramework(cfg, results_dir_path)
        for test in framework.generate_test_plan():
            deployment_id = test.get('deployment_id')
            params = test.get('parameters', {})
            
            # Build smart parameter summary
            param_parts = []
            
            # Cluster size
            if 'cluster_size' in params:
                param_parts.append(f"{params['cluster_size']}n")
            
            # Instance type or memory
            if 'instance_type' in params:
                # Shorten instance type (e.g., t3a.large -> t3a.l, Standard_D4s_v3 -> D4s)
                inst = params['instance_type']
                if inst.startswith('Standard_'):
                    inst = inst.replace('Standard_', '').replace('_v3', '')
                elif '.' in inst:
                    parts = inst.split('.')
                    inst = f"{parts[0]}.{parts[1][0]}"
                param_parts.append(inst)
            elif 'libvirt_memory' in params:
                param_parts.append(f"{params['libvirt_memory']}GB")
                if 'libvirt_vcpus' in params:
                    param_parts.append(f"{params['libvirt_vcpus']}cpu")
            
            # Storage
            if 'data_volumes_per_node' in params and 'data_volume_size' in params:
                vols = params['data_volumes_per_node']
                size = params['data_volume_size']
                if vols > 1:
                    param_parts.append(f"{vols}×{size}GB")
                else:
                    param_parts.append(f"{size}GB")
            
            # Special features
            if params.get('enable_vxlan'):
                param_parts.append('vxlan')
            if params.get('enable_spot_instances'):
                param_parts.append('spot')
            
            params_str = ', '.join(param_parts) if param_parts else 'default'
            
            # Get workflow steps if available
            suite_config = None
            for suite_name, suite in framework.config.get('test_suites', {}).items():
                if suite_name == test.get('suite'):
                    suite_config = suite
                    break
            
            workflow_steps = []
            if suite_config and 'workflow' in suite_config:
                for step in suite_config.get('workflow', []):
                    step_type = step.get('step', 'unknown')
                    # Skip 'validate' steps in display
                    if step_type != 'validate':
                        workflow_steps.append(step_type)
            
            tests_by_provider[test.get('provider', 'unknown')].append({
                'deployment_id': deployment_id,
                'suite': test.get('suite'),
                'params': params_str,
                'workflow': workflow_steps
            })

    if not tests_by_provider:
        print("No tests available.")
        sys.exit(0)

    # Filter by provider if specified
    if provider_filter:
        filtered = {k: v for k, v in tests_by_provider.items() if k.lower() == provider_filter}
        if not filtered:
            print(f"No tests found for provider: {provider_filter}", file=sys.stderr)
            sys.exit(1)
        tests_by_provider = filtered

    for provider in sorted(tests_by_provider):
        tests = sorted(tests_by_provider[provider], key=lambda item: item['suite'])
        
        # Calculate column widths
        max_suite_len = max(len(t['suite']) for t in tests)
        max_params_len = max(len(t['params']) for t in tests)
        
        # Print header
        print(f"\n{'='*100}")
        print(f"Provider: {provider.upper()}")
        print(f"{'='*100}")
        print(f"{'Suite':<{max_suite_len}}  {'Resources':<{max_params_len}}  {'Workflow Steps'}")
        print(f"{'-'*max_suite_len}  {'-'*max_params_len}  {'-'*40}")
        
        # Print tests
        for entry in tests:
            workflow_str = ' → '.join(entry['workflow']) if entry['workflow'] else 'N/A'
            print(f"{entry['suite']:<{max_suite_len}}  {entry['params']:<{max_params_len}}  {workflow_str}")

    print(f"\n{'='*100}")
    print(f"Total: {sum(len(tests) for tests in tests_by_provider.values())} tests across {len(tests_by_provider)} providers")
    print(f"{'='*100}\n")


def resolve_selected_tests(results_dir: str, requested_ids: str, configs: list) -> None:
    """Resolve test suite names/IDs to config files."""
    from tests.e2e.e2e_framework import E2ETestFramework
    
    results_dir_path = Path(results_dir) if results_dir else None
    requested = {value.strip() for value in requested_ids.split(',') if value.strip()}

    if not requested:
        sys.exit(0)

    found = set()
    for cfg in configs:
        try:
            framework = E2ETestFramework(cfg, results_dir_path)
        except ValueError as e:
            # Configuration validation failed - error already printed to stderr
            # Skip this config and continue with others
            continue
        
        for test in framework.generate_test_plan():
            deployment_id = test.get('deployment_id')
            suite = test.get('suite', '')
            # Match by suite name or deployment ID
            if deployment_id in requested or suite in requested:
                provider = test.get('provider', '')
                print(f"FOUND|{suite}|{cfg}|{provider}|{suite}")
                found.add(deployment_id)
                found.add(suite)

    for missing in sorted(requested - found):
        print(f"MISSING|{missing}")


def get_suite_info_from_results(results_file: str, suite_name: str) -> None:
    """Extract config path and provider for a suite from results.json."""
    with open(results_file) as f:
        data = json.load(f)
        for test in data.get('results', []):
            if test.get('suite_name') == suite_name or test.get('deployment_id') == suite_name:
                config_path = test.get('config_path', '')
                provider = test.get('provider', '')
                print(f"{config_path}|{provider}")
                sys.exit(0)
        sys.exit(1)


def get_progress_from_results(results_file: str) -> None:
    """Extract progress information from results.json."""
    try:
        with open(results_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
            results = data.get('results', [])
            total = len(results)
            completed = sum(1 for r in results if 'success' in r)
            if total > 0:
                print(f'{completed}/{total}')
            else:
                print('0/0')
    except Exception:
        print('initializing')


def main():
    """Main entry point for command-line usage."""
    if len(sys.argv) < 2:
        print("Usage: e2e_shell_helpers.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  print_failures <results_file>", file=sys.stderr)
        print("  tail_failed_logs <failures_json>", file=sys.stderr)
        print("  list_tests <results_dir> <provider_filter> <config1> [config2...]", file=sys.stderr)
        print("  resolve_tests <results_dir> <ids> <config1> [config2...]", file=sys.stderr)
        print("  get_suite_info <results_file> <suite_name>", file=sys.stderr)
        print("  get_progress <results_file>", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "print_failures":
        if len(sys.argv) != 3:
            print("Usage: print_failures <results_file>", file=sys.stderr)
            sys.exit(1)
        print_failures(sys.argv[2])

    elif command == "tail_failed_logs":
        if len(sys.argv) != 3:
            print("Usage: tail_failed_logs <failures_json>", file=sys.stderr)
            sys.exit(1)
        tail_failed_logs(sys.argv[2])

    elif command == "list_tests":
        if len(sys.argv) < 5:
            print("Usage: list_tests <results_dir> <provider_filter> <config1> [config2...]", file=sys.stderr)
            sys.exit(1)
        list_tests_for_configs(sys.argv[2], sys.argv[3], sys.argv[4:])

    elif command == "resolve_tests":
        if len(sys.argv) < 5:
            print("Usage: resolve_tests <results_dir> <ids> <config1> [config2...]", file=sys.stderr)
            sys.exit(1)
        resolve_selected_tests(sys.argv[2], sys.argv[3], sys.argv[4:])

    elif command == "get_suite_info":
        if len(sys.argv) != 4:
            print("Usage: get_suite_info <results_file> <suite_name>", file=sys.stderr)
            sys.exit(1)
        get_suite_info_from_results(sys.argv[2], sys.argv[3])

    elif command == "get_progress":
        if len(sys.argv) != 3:
            print("Usage: get_progress <results_file>", file=sys.stderr)
            sys.exit(1)
        get_progress_from_results(sys.argv[2])

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
