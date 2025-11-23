#!/usr/bin/env bash
# Unit tests for template validation (Terraform/OpenTofu and Ansible)
# This test generates templates for each cloud provider and validates them

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure a modern bash and Homebrew path when running on macOS
if [[ -z "${BASH_VERSINFO:-}" || ${BASH_VERSINFO[0]} -lt 4 ]]; then
    for candidate in "$HOME/.local/homebrew/bin/bash" "/usr/local/bin/bash"; do
        if [[ -x "$candidate" ]]; then
            exec "$candidate" "$0" "$@"
        fi
    done
fi
export PATH="$HOME/.local/homebrew/bin:/usr/local/bin:$PATH"

source "$TEST_DIR/test_helper.sh"

# Source the libraries we're testing
LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/versions.sh"
source "$LIB_DIR/cmd_init.sh"

echo "Testing template validation (Terraform + Ansible)"
echo "================================================="

tofu_init_strict() {
    local label="$1"
    local tmp
    tmp=$(mktemp)
    if tofu init >"$tmp" 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} ${label}: tofu init successful"
        rm -f "$tmp"
        return 0
    fi

    if grep -qi "snap-confine has elevated permissions" "$tmp" || grep -qi "snapd.apparmor" "$tmp"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} ${label}: tofu init skipped (snap sandbox/apparmor not available)"
        rm -f "$tmp"
        return 2
    fi

    # Offline or registry unavailable: treat as skipped so suites can pass in restricted environments
    if grep -qi "Failed to resolve provider packages" "$tmp" && grep -qi "registry.opentofu.org" "$tmp"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} ${label}: tofu init skipped (registry unreachable/offline)"
        rm -f "$tmp"
        return 2
    fi

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} ${label}: tofu init failed"
    cat "$tmp"
    rm -f "$tmp"
    return 1
}

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
        echo -e "${YELLOW}⊘${NC} tofu is not available (skipping Terraform validation tests)"
        tools_available=false
    fi

    if command -v ansible-playbook >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} ansible-playbook is available"
    else
        echo -e "${YELLOW}⊘${NC} ansible-playbook is not available (skipping Ansible validation tests)"
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
    local rc=0
    if ! tofu_init_strict "AWS"; then
        rc=$?
        cd - >/dev/null || exit 1
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
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
    if ! tofu_init_strict "Azure"; then
        rc=$?
        cd - >/dev/null
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
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
    if ! tofu_init_strict "GCP"; then
        rc=$?
        cd - >/dev/null
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
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
    if ! tofu_init_strict "Hetzner"; then
        rc=$?
        cd - >/dev/null
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
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
    if ! tofu_init_strict "DigitalOcean"; then
        rc=$?
        cd - >/dev/null
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
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

# Test: Libvirt template validation
test_libvirt_template_validation() {
    echo ""
    echo "Test: Libvirt template validation"

    if ! command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (tofu not available)"
        return
    fi

    local test_dir=$(setup_test_dir)

    # Initialize libvirt deployment with custom options (skip provider checks for testing)
    EXASOL_SKIP_PROVIDER_CHECKS=1 cmd_init --cloud-provider libvirt --deployment-dir "$test_dir" \
        --libvirt-memory 8 --libvirt-vcpus 4 --libvirt-network virbr0 --libvirt-pool default 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Check that libvirt-specific files exist
    if [[ ! -f "$test_dir/.templates/main.tf" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Libvirt main.tf not found"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Check that main.tf contains libvirt-specific resources
    if ! grep -q "provider \"libvirt\"" "$test_dir/.templates/main.tf" || \
       ! grep -q "resource \"libvirt_domain\"" "$test_dir/.templates/main.tf" || \
       ! grep -q "resource \"libvirt_volume\"" "$test_dir/.templates/main.tf"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Libvirt main.tf missing required resources"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Check that variables.tf contains libvirt-specific variables
    if [[ -f "$test_dir/.templates/variables.tf" ]]; then
        if ! grep -q "libvirt_memory_gb" "$test_dir/.templates/variables.tf" || \
           ! grep -q "libvirt_vcpus" "$test_dir/.templates/variables.tf" || \
           ! grep -q "libvirt_network_bridge" "$test_dir/.templates/variables.tf"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Libvirt variables.tf missing required variables"
            cleanup_test_dir "$test_dir"
            return
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Libvirt variables.tf not found"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Check that variables.auto.tfvars contains libvirt values
    if [[ -f "$test_dir/variables.auto.tfvars" ]]; then
        if ! grep -q "libvirt_memory_gb\s*=\s*8" "$test_dir/variables.auto.tfvars" || \
           ! grep -q "libvirt_vcpus\s*=\s*4" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Libvirt variables.auto.tfvars missing custom values"
            cleanup_test_dir "$test_dir"
            return
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} variables.auto.tfvars not found"
        cleanup_test_dir "$test_dir"
        return
    fi

    # Run tofu init (this will fail if libvirt provider is not available, but that's expected)
    cd "$test_dir/.templates" || exit 1
    if timeout 30 tofu init >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Libvirt: tofu init successful"
        
        # Run tofu validate
        if timeout 30 tofu validate >/dev/null 2>&1; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Libvirt: tofu validate successful"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Libvirt: tofu validate failed"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Libvirt: tofu init failed (expected if libvirt provider not available)"
    fi

    cd - >/dev/null
    cleanup_test_dir "$test_dir"
}

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
    local yaml_files
    mapfile -t yaml_files < <(find "$TEST_DIR/.." -name "*.yml" -o -name "*.yaml" | sort)

    if [[ ${#yaml_files[@]} -eq 0 ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} No YAML files found"
        return
    fi

    local total_files=${#yaml_files[@]}

    # Use yamllint with relaxed rules (focus on syntax errors, not style)
    # We disable line-length, comments-indentation, and truthy to focus on actual syntax errors
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
        # Only warnings, no errors - still pass
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} All YAML files have valid syntax ($total_files files, some warnings)"
    fi
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
    EXASOL_SKIP_PROVIDER_CHECKS=1 cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null

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

    local ansible_tmp="$test_dir/.ansible-tmp"
    mkdir -p "$ansible_tmp"

    # Run ansible-playbook syntax check with dummy inventory
    cd "$test_dir/.templates" || exit 1
    local ansible_log
    ansible_log=$(mktemp)
    if LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
        ANSIBLE_LOCAL_TEMP="$ansible_tmp" ANSIBLE_REMOTE_TEMP="$ansible_tmp" \
        ansible-playbook -i dummy_inventory.ini --syntax-check setup-exasol-cluster.yml >"$ansible_log" 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Ansible playbook syntax is valid"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Ansible playbook syntax check failed"
        cat "$ansible_log"
    fi
    rm -f "$ansible_log"

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

    local providers=("aws" "azure" "gcp" "hetzner" "digitalocean" "libvirt")
    local all_have_common=true

    for provider in "${providers[@]}"; do
        local test_dir=$(setup_test_dir)

        if [[ "$provider" == "libvirt" ]]; then
            EXASOL_SKIP_PROVIDER_CHECKS=1 cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" 2>/dev/null
        else
            cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" 2>/dev/null
        fi

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

# Test: Terraform symlinks are created correctly
test_terraform_symlinks() {
    echo ""
    echo "Test: Terraform file symlinks in deployment directory"

    local providers=("aws" "azure" "gcp" "hetzner" "digitalocean" "libvirt")
    local required_symlinks=("common.tf" "main.tf" "variables.tf" "outputs.tf" "inventory.tftpl")

    for provider in "${providers[@]}"; do
        local test_dir=$(setup_test_dir)
        if [[ "$provider" == "libvirt" ]]; then
            EXASOL_SKIP_PROVIDER_CHECKS=1 cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" 2>/dev/null
        else
            cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" 2>/dev/null
        fi

        local all_symlinks_valid=true

        for symlink in "${required_symlinks[@]}"; do
            if [[ -L "$test_dir/$symlink" ]]; then
                # Check that symlink target exists and is readable
                if [[ -f "$test_dir/$symlink" ]]; then
                    continue  # Symlink is valid
                else
                    TESTS_TOTAL=$((TESTS_TOTAL + 1))
                    TESTS_FAILED=$((TESTS_FAILED + 1))
                    echo -e "${RED}✗${NC} $provider: Symlink broken: $symlink"
                    all_symlinks_valid=false
                    break
                fi
            else
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_FAILED=$((TESTS_FAILED + 1))
                echo -e "${RED}✗${NC} $provider: Symlink not created: $symlink"
                all_symlinks_valid=false
                break
            fi
        done

        if [[ "$all_symlinks_valid" == true ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} $provider: All Terraform symlinks valid (${#required_symlinks[@]}/${#required_symlinks[@]})"
        fi

        cleanup_test_dir "$test_dir"
    done
}

# Test: Symlinks work with tofu commands from deployment directory
test_symlinks_with_tofu() {
    echo ""
    echo "Test: Terraform commands work from deployment directory"

    if ! command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (tofu not available)"
        return
    fi

    local test_dir=$(setup_test_dir)
    cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null

    # Run tofu init from deployment directory (not .templates)
    cd "$test_dir" || exit 1
    if tofu_init_strict "tofu init from deployment directory"; then
        # Run tofu validate from deployment directory
        if tofu validate >/dev/null 2>&1; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} tofu validate works from deployment directory"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} tofu validate failed from deployment directory"
        fi
    else
        rc=$?
        if [[ $rc -eq 2 ]]; then
            cd - >/dev/null
            cleanup_test_dir "$test_dir"
            return
        fi
    fi

    cd - >/dev/null
    cleanup_test_dir "$test_dir"
}

# Run all tests
check_tool_availability
test_yaml_syntax_validation
test_aws_template_validation
test_azure_template_validation
test_gcp_template_validation
test_hetzner_template_validation
test_digitalocean_template_validation
test_libvirt_template_validation
test_ansible_playbook_validation
test_ansible_template_validation
test_common_template_inclusion
test_terraform_symlinks
test_symlinks_with_tofu

# Show summary
test_summary
