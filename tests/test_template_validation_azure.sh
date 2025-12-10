#!/usr/bin/env bash
# Wrapper to run Azure template validation only

export TEMPLATE_VALIDATION_TARGET="azure"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TEST_FILE_NAME="${SCRIPT_DIR}/test_template_validation_azure.sh"
source "${SCRIPT_DIR}/lib/template_validation_lib.sh"
template_validation_run

# Ensure script exits successfully if all tests passed
exit 0
