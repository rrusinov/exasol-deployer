#!/usr/bin/env bash
# Ansible and common template validation helpers

# Test: Ansible playbook syntax validation
test_ansible_playbook_validation() {
    echo ""
    echo "Test: Ansible playbook syntax validation"

    if ! command -v ansible-playbook >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (ansible-playbook not available)"
        return
    fi

    local test_dir
    test_dir=$(setup_test_dir)

    EXASOL_SKIP_PROVIDER_CHECKS=1 cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -f "$test_dir/.templates/setup-exasol-cluster.yml" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Ansible playbook not found"
        cleanup_test_dir "$test_dir"
        return
    fi

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

    local test_dir
    test_dir=$(setup_test_dir)

    cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null

    local templates_found=0
    local templates_valid=0

    if [[ -f "$test_dir/.templates/config.j2" ]]; then
        templates_found=$((templates_found + 1))
        if grep -q "{{.*}}" "$test_dir/.templates/config.j2" && \
           ! grep -q "{{[^}]*$" "$test_dir/.templates/config.j2"; then
            templates_valid=$((templates_valid + 1))
        fi
    fi

    if [[ -f "$test_dir/.templates/exasol-data-symlinks.sh.j2" ]]; then
        templates_found=$((templates_found + 1))
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

    for provider in "${providers[@]}"; do
        local test_dir
        test_dir=$(setup_test_dir)

        if [[ "$provider" == "libvirt" ]]; then
            if ! EXASOL_SKIP_PROVIDER_CHECKS=1 cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" 2>/dev/null; then
                echo "Warning: cmd_init failed for $provider (libvirt), continuing test..."
            fi
        elif [[ "$provider" == "azure" ]]; then
            # Create dummy Azure credentials for template validation
            local creds_file="$test_dir/azure_test_creds.json"
            cat > "$creds_file" << 'EOF'
{
  "appId": "test-app-id",
  "password": "test-password",
  "tenant": "test-tenant",
  "subscriptionId": "test-subscription-id"
}
EOF
            if ! cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" --azure-credentials-file "$creds_file" 2>/dev/null; then
                echo "Warning: cmd_init failed for $provider (azure), continuing test..."
            fi
        else
            if ! cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" 2>/dev/null; then
                echo "Warning: cmd_init failed for $provider, continuing test..."
            fi
        fi

        if [[ -f "$test_dir/.templates/common.tf" ]]; then
            if grep -q "resource \"tls_private_key\" \"exasol_key\"" "$test_dir/.templates/common.tf" && \
               grep -q "resource \"random_id\" \"instance\"" "$test_dir/.templates/common.tf"; then
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_PASSED=$((TESTS_PASSED + 1))
                echo -e "${GREEN}✓${NC} $provider: common.tf included and valid"
            else
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_FAILED=$((TESTS_FAILED + 1))
                echo -e "${RED}✗${NC} $provider: common.tf missing expected resources"
            fi
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} $provider: common.tf not found (init may have failed)"
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
        local test_dir
        test_dir=$(setup_test_dir)
        if [[ "$provider" == "libvirt" ]]; then
            EXASOL_SKIP_PROVIDER_CHECKS=1 cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" 2>/dev/null
        else
            cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" 2>/dev/null
        fi

        local all_symlinks_valid=true

        for symlink in "${required_symlinks[@]}"; do
            if [[ -L "$test_dir/$symlink" ]]; then
                if [[ -f "$test_dir/$symlink" ]]; then
                    continue
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

    local test_dir
    test_dir=$(setup_test_dir)
    cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null

    cd "$test_dir" || exit 1
    if tofu_init_strict "tofu init from deployment directory"; then
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
