#!/usr/bin/env bash
# Unit tests for libvirt provider functionality

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

# Skip provider-specific checks in tests (mkisofs may not be installed)
export EXASOL_SKIP_PROVIDER_CHECKS=1

# Source libraries we're testing
LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/versions.sh"
source "$LIB_DIR/cmd_init.sh"

echo "Testing libvirt provider functionality"
echo "======================================"

# Test: Libvirt provider is in supported providers list
test_libvirt_in_supported_providers() {
    echo ""
    echo "Test: Libvirt provider in supported providers list"

    if [[ -v "SUPPORTED_PROVIDERS[libvirt]" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Libvirt provider found in SUPPORTED_PROVIDERS"
        echo -e "${GREEN}✓${NC} Description: ${SUPPORTED_PROVIDERS[libvirt]}"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Libvirt provider not found in SUPPORTED_PROVIDERS"
    fi
}

# Test: Libvirt-specific command line options are recognized
test_libvirt_command_line_options() {
    echo ""
    echo "Test: Libvirt command line options parsing"

    local test_dir=$(setup_test_dir)

    # Test with all libvirt options
    cmd_init --cloud-provider libvirt --deployment-dir "$test_dir" \
        --libvirt-memory 16 --libvirt-vcpus 8 --libvirt-network br0 --libvirt-pool exasol \
        --cluster-size 2 --data-volume-size 200 2>/dev/null

    if [[ -f "$test_dir/variables.auto.tfvars" ]]; then
        local all_options_found=true

        # Check each libvirt-specific variable
        if grep -q "libvirt_memory_gb = 16" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} libvirt_memory_gb correctly set"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} libvirt_memory_gb not found or incorrect"
            all_options_found=false
        fi

        if grep -q "libvirt_vcpus = 8" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} libvirt_vcpus correctly set"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} libvirt_vcpus not found or incorrect"
            all_options_found=false
        fi

        if grep -q "libvirt_network_bridge = \"br0\"" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} libvirt_network_bridge correctly set"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} libvirt_network_bridge not found or incorrect"
            all_options_found=false
        fi

        if grep -q "libvirt_disk_pool = \"exasol\"" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} libvirt_disk_pool correctly set"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} libvirt_disk_pool not found or incorrect"
            all_options_found=false
        fi

        if [[ "$all_options_found" == true ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} All libvirt options correctly parsed"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} variables.auto.tfvars not created"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Libvirt default values are applied
test_libvirt_default_values() {
    echo ""
    echo "Test: Libvirt default values"

    local test_dir=$(setup_test_dir)

    # Test with default values (no libvirt options specified)
    cmd_init --cloud-provider libvirt --deployment-dir "$test_dir" 2>/dev/null

    if [[ -f "$test_dir/variables.auto.tfvars" ]]; then
        local all_defaults_correct=true

        # Check default memory (4GB)
        if grep -q "libvirt_memory_gb = 4" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Default libvirt_memory_gb=4 applied"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Default libvirt_memory_gb not correct"
            all_defaults_correct=false
        fi

        # Check default vCPUs (2)
        if grep -q "libvirt_vcpus = 2" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Default libvirt_vcpus=2 applied"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Default libvirt_vcpus not correct"
            all_defaults_correct=false
        fi

        # Check default network (default)
        if grep -q "libvirt_network_bridge = \"default\"" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Default libvirt_network_bridge=default applied"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Default libvirt_network_bridge not correct"
            all_defaults_correct=false
        fi

        # Check default pool (default)
        if grep -q "libvirt_disk_pool = \"default\"" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Default libvirt_disk_pool=default applied"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Default libvirt_disk_pool not correct"
            all_defaults_correct=false
        fi

        if [[ "$all_defaults_correct" == true ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} All libvirt defaults correctly applied"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} variables.auto.tfvars not created"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Libvirt templates are copied correctly
test_libvirt_template_copy() {
    echo ""
    echo "Test: Libvirt template copying"

    local test_dir=$(setup_test_dir)

    cmd_init --cloud-provider libvirt --deployment-dir "$test_dir" 2>/dev/null

    if [[ -d "$test_dir/.templates" ]]; then
        local required_files=("main.tf" "variables.tf" "outputs.tf")
        local unexpected_files=("cloud-init.cfg" "domain.xslt")
        local all_files_found=true
        local no_duplicate_templates=true

        for file in "${required_files[@]}"; do
            if [[ -f "$test_dir/.templates/$file" ]]; then
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_PASSED=$((TESTS_PASSED + 1))
                echo -e "${GREEN}✓${NC} Template file found: $file"
            else
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_FAILED=$((TESTS_FAILED + 1))
                echo -e "${RED}✗${NC} Template file missing: $file"
                all_files_found=false
            fi
        done

        for file in "${unexpected_files[@]}"; do
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            if [[ -e "$test_dir/.templates/$file" ]]; then
                TESTS_FAILED=$((TESTS_FAILED + 1))
                echo -e "${RED}✗${NC} Found provider-specific duplicate template: $file"
                no_duplicate_templates=false
            else
                TESTS_PASSED=$((TESTS_PASSED + 1))
                echo -e "${GREEN}✓${NC} No duplicate template present: $file"
            fi
        done

        if [[ "$all_files_found" == true && "$no_duplicate_templates" == true ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} All libvirt template files copied"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Libvirt README generation
test_libvirt_readme_generation() {
    echo ""
    echo "Test: Libvirt README generation"

    local test_dir=$(setup_test_dir)

    cmd_init --cloud-provider libvirt --deployment-dir "$test_dir" \
        --libvirt-memory 8 --libvirt-vcpus 4 2>/dev/null

    if [[ -f "$test_dir/README.md" ]]; then
        local readme_content=$(cat "$test_dir/README.md")
        
        # Check for libvirt-specific content
        if echo "$readme_content" | grep -q "Local libvirt/KVM deployment"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} README contains libvirt provider description"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} README missing libvirt provider description"
        fi

        if echo "$readme_content" | grep -q "\*\*Memory\*\*: 8GB per VM"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} README contains memory configuration"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} README missing memory configuration"
        fi

        if echo "$readme_content" | grep -q "\*\*vCPUs\*\*: 4 per VM"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} README contains vCPU configuration"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} README missing vCPU configuration"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} README.md not created"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Libvirt instance type mapping
test_libvirt_instance_type_mapping() {
    echo ""
    echo "Test: Libvirt instance type mapping"

    local test_dir=$(setup_test_dir)

    cmd_init --cloud-provider libvirt --deployment-dir "$test_dir" 2>/dev/null

    if [[ -f "$test_dir/variables.auto.tfvars" ]]; then
        if grep -q "instance_type = \"libvirt-custom\"" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Libvirt instance type correctly mapped"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Libvirt instance type not correctly mapped"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} variables.auto.tfvars not created"
    fi

    cleanup_test_dir "$test_dir"
}

# Run all tests
test_libvirt_in_supported_providers
test_libvirt_command_line_options
test_libvirt_default_values
test_libvirt_template_copy
test_libvirt_readme_generation
test_libvirt_instance_type_mapping

# Show summary
test_summary
