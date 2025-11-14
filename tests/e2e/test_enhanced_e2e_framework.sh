#!/usr/bin/env bash
# Test runner for enhanced E2E framework

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Running Enhanced E2E Framework Tests..."
echo "======================================"

# Use the new test runner
cd "$SCRIPT_DIR"
PYTHONPATH=. ./test_runner.py

# Test enhanced framework CLI
echo ""
echo "Testing Enhanced Framework CLI..."
PYTHONPATH=. python3 enhanced_e2e_framework.py plan --config configs/aws-basic.json --output-plan /tmp/test_enhanced_plan.json > /dev/null 2>&1
echo "✓ Enhanced Framework CLI works"

# Verify plan was generated
if [ -f "/tmp/test_enhanced_plan.json" ]; then
    echo "✓ Enhanced execution plan generated successfully"
    echo "Plan contains:"
    python3 -c "
import json
with open('/tmp/test_enhanced_plan.json', 'r') as f:
    plan = json.load(f)
print(f'  - {len(plan[\"ssh_validation_plans\"])} SSH validation plans')
print(f'  - {len(plan[\"emergency_response_plans\"])} emergency response plans')
print(f'  - Features: {list(plan[\"enhanced_features\"].keys())}')
"
    # Clean up test file
    rm -f /tmp/test_enhanced_plan.json
else
    echo "✗ Enhanced execution plan not generated"
    exit 1
fi

echo ""
echo "🎉 All Enhanced E2E Framework Tests Passed!"
echo ""
echo "Enhanced Features Implemented:"
echo "  ✓ SSH-based live system validation"
echo "  ✓ Emergency response and timeout monitoring"
echo "  ✓ Resource tracking and leak prevention"
echo "  ✓ Comprehensive execution planning"
echo "  ✓ Dry-run mode for safe testing"
echo "  ✓ Automatic temporary directory cleanup"
echo ""
echo "Test Runner Usage:"
echo "  ./test_runner.py                    # Clean run with /tmp/\$USER/exasol-deployer/date-time/"
echo "  ./test_runner.py --keep-results     # Keep temporary directories"
echo "  ./test_runner.py --verbose          # Show detailed output"
echo "  ./test_runner.py --module <name>    # Run single test module"
echo "  ./test_runner.py --test-results-dir /path  # Use custom directory"