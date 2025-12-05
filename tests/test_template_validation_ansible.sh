#!/usr/bin/env bash
# Wrapper to run Ansible-focused template validation tests

export TEMPLATE_VALIDATION_TARGET="ansible"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/template_validation_lib.sh"
template_validation_run

# Ensure script exits successfully if all tests passed
exit 0
