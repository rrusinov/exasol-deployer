#!/usr/bin/env bash
# Test runner - executes all unit tests

set -e

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Exasol Deployer - Unit Tests${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Track overall results
TOTAL_TEST_FILES=0
PASSED_TEST_FILES=0
FAILED_TEST_FILES=0

# Function to run a test file
run_test_file() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file")

    echo -e "${BLUE}Running: $test_name${NC}"
    echo ""

    TOTAL_TEST_FILES=$((TOTAL_TEST_FILES + 1))

    if bash "$test_file"; then
        PASSED_TEST_FILES=$((PASSED_TEST_FILES + 1))
        echo ""
        return 0
    else
        FAILED_TEST_FILES=$((FAILED_TEST_FILES + 1))
        echo ""
        return 1
    fi
}

# Run all test files
run_test_file "$TEST_DIR/test_shellcheck.sh"
run_test_file "$TEST_DIR/test_common.sh"
run_test_file "$TEST_DIR/test_versions.sh"
run_test_file "$TEST_DIR/test_state.sh"
run_test_file "$TEST_DIR/test_init.sh"
run_test_file "$TEST_DIR/test_power_control.sh"
run_test_file "$TEST_DIR/test_deploy_failures.sh"
run_test_file "$TEST_DIR/test_destroy_failures.sh"
run_test_file "$TEST_DIR/test_status.sh"
run_test_file "$TEST_DIR/test_template_validation.sh"
run_test_file "$TEST_DIR/test_url_availability.sh"
run_test_file "$TEST_DIR/test_documentation.sh"
run_test_file "$TEST_DIR/test_help_options.sh"
run_test_file "$TEST_DIR/test_e2e_framework.sh"

# Overall summary
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Overall Test Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Test Files Run: $TOTAL_TEST_FILES"
echo -e "Passed: ${GREEN}$PASSED_TEST_FILES${NC}"
echo -e "Failed: ${RED}$FAILED_TEST_FILES${NC}"
echo ""

if [[ $FAILED_TEST_FILES -eq 0 ]]; then
    echo -e "${GREEN}✓ All test files passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some test files failed!${NC}"
    exit 1
fi
