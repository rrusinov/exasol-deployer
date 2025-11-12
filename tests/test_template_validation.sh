#!/bin/bash
# Unit tests for template validation (Terraform/OpenTofu and Ansible)
# This test generates templates for each cloud provider and validates them

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

# Source the libraries we're testing
LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/versions.sh"
source "$LIB_DIR/cmd_init.sh"

echo "Testing template validation (Terraform + Ansible)"
echo "================================================="

# Check if required tools are available
check_tool_availability() {
    echo ""
    echo "Test: Check tool availability"

    local tools_available=true

    if command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} tofu is available"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} tofu is not available (skipping Terraform validation tests)"
        tools_available=false
    fi

    if command -v ansible-playbook >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} ansible-playbook is available"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} ansible-playbook is not available (skipping Ansible validation tests)"
        tools_available=false
    fi

    if [[ "$tools_available" == false ]]; then
        echo -e "${YELLOW}Warning: Some validation tests will be skipped due to missing tools${NC}"
    fi
}

# Test: AWS template validation
test_aws_template_validation() {
    echo ""
    echo "Test: AWS template validation"

    if ! command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (tofu not available)"
        return
    fi

    local test_dir=$(setup_test_dir)

    # Initialize AWS deployment
    cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu init
    cd "$test_dir/.templates" || exit 1
    if tofu init >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} AWS: tofu init successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} AWS: tofu init failed"
        cd - >/dev/null
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu validate
    if tofu validate >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} AWS: tofu validate successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} AWS: tofu validate failed"
    fi

    cd - >/dev/null
    cleanup_test_dir "$test_dir"
}

# Test: Azure template validation
test_azure_template_validation() {
    echo ""
    echo "Test: Azure template validation"

    if ! command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (tofu not available)"
        return
    fi

    local test_dir=$(setup_test_dir)

    # Initialize Azure deployment
    cmd_init --cloud-provider azure --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu init
    cd "$test_dir/.templates" || exit 1
    if tofu init >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Azure: tofu init successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Azure: tofu init failed"
        cd - >/dev/null
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu validate
    if tofu validate >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Azure: tofu validate successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Azure: tofu validate failed"
    fi

    cd - >/dev/null
    cleanup_test_dir "$test_dir"
}

# Test: GCP template validation
test_gcp_template_validation() {
    echo ""
    echo "Test: GCP template validation"

    if ! command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (tofu not available)"
        return
    fi

    local test_dir=$(setup_test_dir)

    # Initialize GCP deployment
    cmd_init --cloud-provider gcp --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu init
    cd "$test_dir/.templates" || exit 1
    if tofu init >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} GCP: tofu init successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} GCP: tofu init failed"
        cd - >/dev/null
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu validate
    if tofu validate >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} GCP: tofu validate successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} GCP: tofu validate failed"
    fi

    cd - >/dev/null
    cleanup_test_dir "$test_dir"
}

# Test: Hetzner template validation
test_hetzner_template_validation() {
    echo ""
    echo "Test: Hetzner template validation"

    if ! command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (tofu not available)"
        return
    fi

    local test_dir=$(setup_test_dir)

    # Initialize Hetzner deployment
    cmd_init --cloud-provider hetzner --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu init
    cd "$test_dir/.templates" || exit 1
    if tofu init >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Hetzner: tofu init successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Hetzner: tofu init failed"
        cd - >/dev/null
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu validate
    if tofu validate >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Hetzner: tofu validate successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Hetzner: tofu validate failed"
    fi

    cd - >/dev/null
    cleanup_test_dir "$test_dir"
}

# Test: DigitalOcean template validation
test_digitalocean_template_validation() {
    echo ""
    echo "Test: DigitalOcean template validation"

    if ! command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (tofu not available)"
        return
    fi

    local test_dir=$(setup_test_dir)

    # Initialize DigitalOcean deployment
    cmd_init --cloud-provider digitalocean --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu init
    cd "$test_dir/.templates" || exit 1
    if tofu init >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} DigitalOcean: tofu init successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} DigitalOcean: tofu init failed"
        cd - >/dev/null
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu validate
    if tofu validate >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} DigitalOcean: tofu validate successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} DigitalOcean: tofu validate failed"
    fi

    cd - >/dev/null
    cleanup_test_dir "$test_dir"
}

# Test: Ansible playbook syntax validation
test_ansible_playbook_validation() {
    echo ""
    echo "Test: Ansible playbook syntax validation"

    if ! command -v ansible-playbook >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (ansible-playbook not available)"
        return
    fi

    local test_dir=$(setup_test_dir)

    # Initialize deployment (any provider will do, Ansible is cloud-agnostic)
    cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -f "$test_dir/.templates/setup-exasol-cluster.yml" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Ansible playbook not found"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Create a dummy inventory file for syntax checking
    cat > "$test_dir/.templates/dummy_inventory.ini" <<EOF
[exasol_nodes]
n11 ansible_host=10.0.0.1 ansible_user=exasol private_ip=10.0.0.1 data_volume_ids='["vol-1"]'

[exasol_nodes:vars]
ansible_user=exasol
ansible_ssh_private_key_file=/dev/null
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

    # Run ansible-playbook syntax check with dummy inventory
    cd "$test_dir/.templates" || exit 1
    if ansible-playbook -i dummy_inventory.ini --syntax-check setup-exasol-cluster.yml >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Ansible playbook syntax is valid"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Ansible playbook syntax check failed"
    fi

    cd - >/dev/null
    cleanup_test_dir "$test_dir"
}

# Test: Ansible template files validation
test_ansible_template_validation() {
    echo ""
    echo "Test: Ansible template files validation"

    if ! command -v ansible-playbook >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (ansible-playbook not available)"
        return
    fi

    local test_dir=$(setup_test_dir)

    # Initialize deployment
    cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null

    # Check for Jinja2 template files
    local templates_found=0
    local templates_valid=0

    if [[ -f "$test_dir/.templates/config.j2" ]]; then
        templates_found=$((templates_found + 1))
        # Basic Jinja2 syntax check - look for unclosed tags
        if grep -q "{{.*}}" "$test_dir/.templates/config.j2" && \
           ! grep -q "{{[^}]*$" "$test_dir/.templates/config.j2"; then
            templates_valid=$((templates_valid + 1))
        fi
    fi

    if [[ -f "$test_dir/.templates/exasol-data-symlinks.sh.j2" ]]; then
        templates_found=$((templates_found + 1))
        # Basic Jinja2 syntax check
        if grep -q "{{.*}}" "$test_dir/.templates/exasol-data-symlinks.sh.j2" && \
           ! grep -q "{{[^}]*$" "$test_dir/.templates/exasol-data-symlinks.sh.j2"; then
            templates_valid=$((templates_valid + 1))
        fi
    fi

    if [[ $templates_found -eq $templates_valid ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Ansible Jinja2 templates are valid ($templates_valid/$templates_found)"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Some Ansible templates have syntax issues ($templates_valid/$templates_found valid)"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Common template is included in all providers
test_common_template_inclusion() {
    echo ""
    echo "Test: Common template inclusion in all providers"

    local providers=("aws" "azure" "gcp" "hetzner" "digitalocean")
    local all_have_common=true

    for provider in "${providers[@]}"; do
        local test_dir=$(setup_test_dir)

        cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" 2>/dev/null

        if [[ -f "$test_dir/.templates/common.tf" ]]; then
            # Check that common.tf contains the expected resources
            if grep -q "resource \"tls_private_key\" \"exasol_key\"" "$test_dir/.templates/common.tf" && \
               grep -q "resource \"random_id\" \"instance\"" "$test_dir/.templates/common.tf"; then
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_PASSED=$((TESTS_PASSED + 1))
                echo -e "${GREEN}✓${NC} $provider: common.tf included and valid"
            else
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_FAILED=$((TESTS_FAILED + 1))
                echo -e "${RED}✗${NC} $provider: common.tf missing expected resources"
                all_have_common=false
            fi
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} $provider: common.tf not found"
            all_have_common=false
        fi

        cleanup_test_dir "$test_dir"
    done
}

# Run all tests
check_tool_availability
test_aws_template_validation
test_azure_template_validation
test_gcp_template_validation
test_hetzner_template_validation
test_digitalocean_template_validation
test_ansible_playbook_validation
test_ansible_template_validation
test_common_template_inclusion

# Show summary
test_summary
