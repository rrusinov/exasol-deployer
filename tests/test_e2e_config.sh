#!/usr/bin/env bash
# Unit tests for E2E framework configuration structure

if [[ -n "${__TEST_E2E_CONFIG_SH_INCLUDED__:-}" ]]; then return 0; fi
readonly __TEST_E2E_CONFIG_SH_INCLUDED__=1

set -euo pipefail

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_DIR="${SCRIPT_DIR}/e2e"
CONFIGS_DIR="${E2E_DIR}/configs"

# Source test helper
source "${SCRIPT_DIR}/test_helper.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_config_structure() {
    local test_name="$1"
    echo "Testing: $test_name"
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ PASS"
}

test_fail() {
    local message="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: $message"
}

# Test 1: Verify config directories exist
test_config_structure "Config directories exist"
if [[ -d "$CONFIGS_DIR/sut" ]] && [[ -d "$CONFIGS_DIR/workflow" ]]; then
    test_pass
else
    test_fail "Missing sut/ or workflow/ directories"
fi

# Test 2: Verify SUT configs are valid JSON
test_config_structure "SUT configs are valid JSON"
sut_valid=true
for sut_file in "$CONFIGS_DIR"/sut/*.json; do
    if [[ -f "$sut_file" ]]; then
        if ! python3 -c "import json; json.load(open('$sut_file'))" 2>/dev/null; then
            sut_valid=false
            test_fail "Invalid JSON in $sut_file"
            break
        fi
    fi
done
if $sut_valid; then
    test_pass
fi

# Test 3: Verify workflow configs are valid JSON
test_config_structure "Workflow configs are valid JSON"
workflow_valid=true
for workflow_file in "$CONFIGS_DIR"/workflow/*.json; do
    if [[ -f "$workflow_file" ]]; then
        if ! python3 -c "import json; json.load(open('$workflow_file'))" 2>/dev/null; then
            workflow_valid=false
            test_fail "Invalid JSON in $workflow_file"
            break
        fi
    fi
done
if $workflow_valid; then
    test_pass
fi

# Test 4: Verify provider configs reference valid SUT and workflow files
test_config_structure "Provider configs reference valid files"
provider_refs_valid=true
for provider_file in "$CONFIGS_DIR"/{aws,azure,gcp,libvirt}.json; do
    if [[ -f "$provider_file" ]]; then
        # Extract SUT and workflow references
        refs=$(python3 <<EOF
import json
with open('$provider_file') as f:
    data = json.load(f)
    for suite in data.get('test_suites', []):
        print(suite.get('sut', ''))
        print(suite.get('workflow', ''))
EOF
)
        while IFS= read -r ref; do
            if [[ -n "$ref" ]]; then
                ref_file="$CONFIGS_DIR/$ref"
                if [[ ! -f "$ref_file" ]]; then
                    provider_refs_valid=false
                    test_fail "Referenced file not found: $ref_file"
                    break 2
                fi
            fi
        done <<< "$refs"
    fi
done
if $provider_refs_valid; then
    test_pass
fi

# Test 5: Verify workflow steps have valid step types
test_config_structure "Workflow steps have valid step types"
workflow_steps_valid=true
valid_steps="init|deploy|validate|destroy|stop_cluster|start_cluster|stop_node|start_node|restart_node|crash_node|custom_command"
for workflow_file in "$CONFIGS_DIR"/workflow/*.json; do
    if [[ -f "$workflow_file" ]]; then
        invalid_steps=$(python3 <<EOF
import json
with open('$workflow_file') as f:
    data = json.load(f)
    valid = '$valid_steps'.split('|')
    invalid = [step.get('step', 'unknown') for step in data.get('steps', []) 
               if step.get('step') not in valid]
    print(','.join(invalid))
EOF
)
        if [[ -n "$invalid_steps" ]]; then
            workflow_steps_valid=false
            test_fail "$workflow_file has invalid steps: $invalid_steps"
            break
        fi
    fi
done
if $workflow_steps_valid; then
    test_pass
fi

# Test 6: Test framework loading for aws.json
test_config_structure "Framework loading for aws.json"
if [[ ! -f "$CONFIGS_DIR/aws.json" ]]; then
    echo "  ⊘ SKIP: aws.json not present"
    test_pass
elif python3 <<EOF
import sys
import os
from pathlib import Path
sys.path.insert(0, '$E2E_DIR')
os.chdir('$SCRIPT_DIR/..')

try:
    from e2e_framework import E2ETestFramework

    results_dir = Path('$SCRIPT_DIR/tmp/test-results')
    results_dir.mkdir(parents=True, exist_ok=True)
    
    # Create framework instance
    framework = E2ETestFramework('$CONFIGS_DIR/aws.json', results_dir)
    
    # Try to generate test plan
    test_plan = framework.generate_test_plan(dry_run=True)
    
    # Validate we got some test cases
    if len(test_plan) == 0:
        raise ValueError("No test cases generated")
    
    # Validate structure of test cases
    for test_case in test_plan:
        if 'deployment_id' not in test_case:
            raise ValueError("Test case missing deployment_id")
        if 'provider' not in test_case:
            raise ValueError("Test case missing provider")
    
    print(f"✓ Generated {len(test_plan)} test cases")
    sys.exit(0)
except Exception as e:
    print(f"✗ Error: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF
then
    test_pass
else
    test_fail "Framework loading failed"
fi

# Test 7: Test framework loading for libvirt.json
test_config_structure "Framework loading for libvirt.json"
if [[ ! -f "$CONFIGS_DIR/libvirt.json" ]]; then
    echo "  ⊘ SKIP: libvirt.json not present"
    test_pass
elif python3 <<EOF
import sys
import os
from pathlib import Path
sys.path.insert(0, '$E2E_DIR')
os.chdir('$SCRIPT_DIR/..')

try:
    from e2e_framework import E2ETestFramework

    results_dir = Path('$SCRIPT_DIR/tmp/test-results')
    results_dir.mkdir(parents=True, exist_ok=True)
    
    # Create framework instance
    framework = E2ETestFramework('$CONFIGS_DIR/libvirt.json', results_dir)
    
    # Try to generate test plan
    test_plan = framework.generate_test_plan(dry_run=True)
    
    # Validate we got some test cases
    if len(test_plan) == 0:
        raise ValueError("No test cases generated")
    
    # Validate structure and that files were loaded
    for test_case in test_plan:
        if 'deployment_id' not in test_case:
            raise ValueError("Test case missing deployment_id")
        if 'provider' not in test_case:
            raise ValueError("Test case missing provider")
        if test_case['provider'] != 'libvirt':
            raise ValueError(f"Expected provider 'libvirt', got '{test_case['provider']}'")
    
    print(f"✓ Generated {len(test_plan)} test cases, files loaded correctly")
    sys.exit(0)
except Exception as e:
    print(f"✗ Error: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF
then
    test_pass
else
    test_fail "Framework loading failed"
fi

# Test 8: Verify all providers have matching provider field
test_config_structure "Provider configs have matching provider field"
provider_field_valid=true
for provider_file in "$CONFIGS_DIR"/{aws,azure,gcp,libvirt}.json; do
    if [[ -f "$provider_file" ]]; then
        provider_name=$(basename "$provider_file" .json)
        config_provider=$(python3 -c "import json; print(json.load(open('$provider_file')).get('provider', ''))")
        if [[ "$provider_name" != "$config_provider" ]]; then
            provider_field_valid=false
            test_fail "Provider mismatch in $provider_file: filename=$provider_name, config=$config_provider"
            break
        fi
    fi
done
if $provider_field_valid; then
    test_pass
fi

# Print summary
echo ""
echo "======================================"
echo "Test Summary:"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "======================================"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
else
    echo "All tests passed!"
    exit 0
fi
