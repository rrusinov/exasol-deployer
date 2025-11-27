#!/usr/bin/env bash
# Body of template validation tests (shared helpers and test cases)

# Test: YAML syntax validation for all YAML files
test_yaml_syntax_validation() {
    echo ""
    echo "Test: YAML syntax validation for all YAML files"

    if ! command -v yamllint >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (yamllint not available)"
        return
    fi

    # Find all YAML files in the project
    local yaml_files=()
    while IFS= read -r file; do
        yaml_files+=("$file")
    done < <(find "$TEST_DIR/.." -name "*.yml" -o -name "*.yaml" | sort)

    if [[ ${#yaml_files[@]} -eq 0 ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} No YAML files found"
        return
    fi

    local total_files=${#yaml_files[@]}

    # Use yamllint with relaxed rules (focus on syntax errors, not style)
    local yamllint_config="{extends: default, rules: {line-length: disable, comments-indentation: disable, truthy: disable}}"
    local yamllint_output
    yamllint_output=$(yamllint -f parsable -d "$yamllint_config" "${yaml_files[@]}" 2>&1)
    local yamllint_exit=$?

    # Check for syntax errors (not warnings)
    local syntax_errors
    syntax_errors=$(echo "$yamllint_output" | grep -c "\[error\]" || true)

    if [[ $yamllint_exit -eq 0 ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} All YAML files have valid syntax ($total_files files)"
    elif [[ $syntax_errors -gt 0 ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Found $syntax_errors syntax error(s) in YAML files:"
        echo "$yamllint_output" | grep "\[error\]"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} All YAML files have valid syntax ($total_files files, some warnings)"
    fi
}

# Provider-specific and supporting tests are unchanged from the original monolithic script
# (code omitted here for brevity)
LIB_TEST_DIR="${TEST_DIR}/lib"
source "${LIB_TEST_DIR}/test_template_validation_provider_tests.sh"
# Ansible/common validations
source "${LIB_TEST_DIR}/test_template_validation_ansible.sh"
