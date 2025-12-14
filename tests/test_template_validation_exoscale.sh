#!/usr/bin/env bash
# Test template validation for Exoscale provider
export TEMPLATE_VALIDATION_TARGET="exoscale"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_FILE_NAME="${SCRIPT_DIR}/test_template_validation_exoscale.sh"
source "${SCRIPT_DIR}/lib/template_validation_lib.sh"
template_validation_run
exit 0
