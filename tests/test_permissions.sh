#!/usr/bin/env bash
# Test permissions functionality

# Source test helpers
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

# Source the libraries we're testing
LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/versions.sh"
source "$LIB_DIR/cmd_init.sh"

echo "Testing permissions functionality"
echo "=================================="

# Test: generate_permissions.sh creates directory structure
test_generate_permissions_creates_directory() {
    echo ""
    echo "Test: generate_permissions.sh creates directory structure"

    local permissions_dir="$LIB_DIR/permissions"
    
    # Run generate permissions script
    # This may fail if pike is not installed, but should at least create the directory
    "$TEST_DIR/../scripts/generate-permissions.sh" >/dev/null 2>&1 || true

    # Check if directory exists
    assert_dir_exists "$permissions_dir"
}

# Test: --show-permissions requires --cloud-provider
test_show_permissions_requires_provider() {
    echo ""
    echo "Test: --show-permissions requires --cloud-provider"

    local test_dir
    test_dir=$(setup_test_dir)
    
    # Test that --show-permissions without provider fails
    local output
    output=$(cmd_init --show-permissions --deployment-dir "$test_dir" 2>&1 || true)
    
    if echo "$output" | grep -q "requires --cloud-provider"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} --show-permissions requires --cloud-provider"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should require --cloud-provider flag"
        echo "  Output was: $output"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: --show-permissions displays permissions for valid provider
test_show_permissions_with_provider() {
    echo ""
    echo "Test: --show-permissions with valid provider"

    local test_dir
    test_dir=$(setup_test_dir)
    
    # Create temp permissions directory
    local temp_lib_dir="$test_dir/lib"
    local temp_permissions_dir="$temp_lib_dir/permissions"
    mkdir -p "$temp_permissions_dir"
    
    # Create dummy permissions file in temp location
    echo '{"Version": "2012-10-17", "Statement": {"Effect": "Allow", "Action": ["ec2:DescribeInstances"], "Resource": "*"}}' > "$temp_permissions_dir/aws.json"

    # Test show permissions with overridden LIB_DIR
    local output
    if output=$(LIB_DIR="$temp_lib_dir" cmd_init --cloud-provider aws --show-permissions 2>&1); then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} --show-permissions displays permissions"
        
        # Check output contains expected content
        if echo "$output" | grep -q "Version"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Output contains permission data"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Output should contain permission data"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} --show-permissions should succeed with valid provider"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: --show-permissions with missing file
test_show_permissions_missing_file() {
    echo ""
    echo "Test: --show-permissions with missing permissions file"

    local test_dir
    test_dir=$(setup_test_dir)
    
    # Create temp permissions directory without hetzner files
    local temp_lib_dir="$test_dir/lib"
    local temp_permissions_dir="$temp_lib_dir/permissions"
    mkdir -p "$temp_permissions_dir"

    # Test show permissions for missing file
    local output
    if output=$(LIB_DIR="$temp_lib_dir" cmd_init --cloud-provider hetzner --show-permissions 2>&1); then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should fail when permissions file is missing"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Fails when permissions file is missing"
        
        # Check error message
        if echo "$output" | grep -q "not found"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Error message indicates file not found"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Should indicate file not found"
        fi
    fi

    cleanup_test_dir "$test_dir"
}

# Test: permissions files are valid JSON (if they exist)
test_permissions_files_valid_json() {
    echo ""
    echo "Test: Permissions files are valid JSON"

    local permissions_dir="$LIB_DIR/permissions"
    
    if [[ ! -d "$permissions_dir" ]]; then
        echo -e "${YELLOW}⊘${NC} Permissions directory doesn't exist, skipping JSON validation"
        return 0
    fi

    local has_files=false
    for provider in aws azure gcp hetzner digitalocean libvirt; do
        local perm_file="$permissions_dir/$provider.json"
        if [[ -f "$perm_file" ]]; then
            has_files=true
            if jq . "$perm_file" >/dev/null 2>&1; then
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_PASSED=$((TESTS_PASSED + 1))
                echo -e "${GREEN}✓${NC} $provider.json is valid JSON"
            else
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_FAILED=$((TESTS_FAILED + 1))
                echo -e "${RED}✗${NC} $provider.json is not valid JSON"
            fi
        fi
    done

    if [[ "$has_files" == "false" ]]; then
        echo -e "${YELLOW}⊘${NC} No permissions files found, run scripts/generate-permissions.sh to create them"
    fi
}

# Run all tests
test_generate_permissions_creates_directory
test_show_permissions_requires_provider
test_show_permissions_with_provider
test_show_permissions_missing_file
test_permissions_files_valid_json

# Show summary
test_summary