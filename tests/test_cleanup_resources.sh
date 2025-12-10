#!/usr/bin/env bash
# Unit tests for scripts/cleanup-resources.sh

if [[ -n "${__TEST_CLEANUP_RESOURCES_INCLUDED__:-}" ]]; then return 0; fi
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly CLEANUP_SCRIPT="$PROJECT_ROOT/scripts/cleanup-resources.sh"

readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_RESET='\033[0m'

test_count=0
pass_count=0
fail_count=0

assert_failure() {
    local exit_code="$1"
    local message="$2"
    
    ((test_count++))
    if [[ $exit_code -ne 0 ]]; then
        ((pass_count++))
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} $message"
        return 0
    else
        ((fail_count++))
        echo -e "${COLOR_RED}✗${COLOR_RESET} $message"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    
    ((test_count++))
    if [[ "$haystack" == *"$needle"* ]]; then
        ((pass_count++))
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} $message"
        return 0
    else
        ((fail_count++))
        echo -e "${COLOR_RED}✗${COLOR_RESET} $message"
        return 1
    fi
}

test_script_exists() {
    ((test_count++))
    if [[ -f "$CLEANUP_SCRIPT" ]]; then
        ((pass_count++))
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} cleanup-resources.sh exists"
    else
        ((fail_count++))
        echo -e "${COLOR_RED}✗${COLOR_RESET} cleanup-resources.sh not found"
    fi
}

test_script_executable() {
    ((test_count++))
    if [[ -x "$CLEANUP_SCRIPT" ]]; then
        ((pass_count++))
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} cleanup-resources.sh is executable"
    else
        ((fail_count++))
        echo -e "${COLOR_RED}✗${COLOR_RESET} cleanup-resources.sh is not executable"
    fi
}

test_help_option() {
    local output
    output=$("$CLEANUP_SCRIPT" --help 2>&1)
    assert_contains "$output" "Usage:" "Help shows usage"
    assert_contains "$output" "--provider" "Help shows --provider option"
    assert_contains "$output" "--prefix" "Help shows --prefix option"
    assert_contains "$output" "--region" "Help shows --region option"
    assert_contains "$output" "--dry-run" "Help shows --dry-run option"
}

test_missing_provider() {
    local output
    output=$("$CLEANUP_SCRIPT" 2>&1)
    local exit_code=$?
    assert_failure "$exit_code" "Fails when provider is missing"
    assert_contains "$output" "Provider is required" "Error message mentions provider"
}

test_invalid_provider() {
    local output exit_code
    output=$("$CLEANUP_SCRIPT" --provider invalid 2>&1)
    exit_code=$?
    assert_failure "$exit_code" "Fails with invalid provider"
    assert_contains "$output" "Unsupported provider" "Error message mentions unsupported provider"
}

test_missing_prefix_value() {
    local output exit_code
    output=$("$CLEANUP_SCRIPT" --provider aws --prefix 2>&1)
    exit_code=$?
    assert_failure "$exit_code" "Fails when --prefix has no value"
    assert_contains "$output" "--prefix requires a value" "Error message mentions missing prefix value"
}

test_missing_region_value() {
    local output exit_code
    output=$("$CLEANUP_SCRIPT" --provider aws --region 2>&1)
    exit_code=$?
    assert_failure "$exit_code" "Fails when --region has no value"
    assert_contains "$output" "--region requires a value" "Error message mentions missing region value"
}

test_missing_provider_value() {
    local output exit_code
    output=$("$CLEANUP_SCRIPT" --provider 2>&1)
    exit_code=$?
    assert_failure "$exit_code" "Fails when --provider has no value"
    assert_contains "$output" "--provider requires a value" "Error message mentions missing provider value"
}

test_valid_providers() {
    local providers=("aws" "azure" "gcp" "hetzner" "digitalocean" "libvirt")
    
    for provider in "${providers[@]}"; do
        # Just test that it doesn't fail on validation (will fail on CLI tool check)
        local output
        output=$("$CLEANUP_SCRIPT" --provider "$provider" --dry-run 2>&1)
        
        ((test_count++))
        if [[ "$output" != *"Unsupported provider"* ]]; then
            ((pass_count++))
            echo -e "${COLOR_GREEN}✓${COLOR_RESET} Provider $provider is recognized"
        else
            ((fail_count++))
            echo -e "${COLOR_RED}✗${COLOR_RESET} Provider $provider not recognized"
        fi
    done
}

test_unknown_option() {
    local output exit_code
    output=$("$CLEANUP_SCRIPT" --unknown-option 2>&1)
    exit_code=$?
    assert_failure "$exit_code" "Fails with unknown option"
    assert_contains "$output" "Unknown option" "Error message mentions unknown option"
}

test_region_only_for_aws() {
    local output exit_code
    output=$("$CLEANUP_SCRIPT" --provider azure --region us-east-1 2>&1)
    exit_code=$?
    assert_failure "$exit_code" "Fails when --region used with non-AWS provider"
    assert_contains "$output" "--region flag is only supported for AWS" "Error message mentions region only for AWS"
}

test_tag_only_for_aws() {
    local output exit_code
    output=$("$CLEANUP_SCRIPT" --provider gcp --tag custom=value 2>&1)
    exit_code=$?
    assert_failure "$exit_code" "Fails when --tag used with non-AWS provider"
    assert_contains "$output" "--tag filtering is only supported for AWS" "Error message mentions tag only for AWS"
}

test_aws_supports_all_features() {
    local output
    output=$("$CLEANUP_SCRIPT" --provider aws --region us-east-1 --tag owner=test --prefix myapp --dry-run 2>&1)
    
    ((test_count++))
    if [[ "$output" != *"only supported for AWS"* && "$output" != *"Unsupported"* ]]; then
        ((pass_count++))
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} AWS supports all features"
    else
        ((fail_count++))
        echo -e "${COLOR_RED}✗${COLOR_RESET} AWS should support all features"
    fi
}

run_all_tests() {
    echo "Running cleanup-resources.sh tests..."
    echo "=========================================="
    
    test_script_exists
    test_script_executable
    test_help_option
    test_missing_provider
    test_invalid_provider
    test_missing_prefix_value
    test_missing_region_value
    test_missing_provider_value
    test_valid_providers
    test_unknown_option
    test_region_only_for_aws
    test_tag_only_for_aws
    test_aws_supports_all_features
    
    echo ""
    echo "=========================================="
    echo "Tests: $test_count, Passed: $pass_count, Failed: $fail_count"
    
    if [[ $fail_count -eq 0 ]]; then
        echo -e "${COLOR_GREEN}All tests passed!${COLOR_RESET}"
        return 0
    else
        echo -e "${COLOR_RED}Some tests failed!${COLOR_RESET}"
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
