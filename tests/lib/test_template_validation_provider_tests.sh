#!/usr/bin/env bash
# Provider-specific template validation tests

# Test: AWS template validation
test_aws_template_validation() {
    echo ""
    echo "Test: AWS template validation"

    if ! command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (tofu not available)"
        return
    fi

    local test_dir
    test_dir=$(setup_test_dir)

    cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null
    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir/.templates" || exit 1
    local rc=0
    if ! tofu_init_strict "AWS"; then
        rc=$?
        cd - >/dev/null || exit 1
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
        return
    fi

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

    local test_dir
    test_dir=$(setup_test_dir)
    cmd_init --cloud-provider azure --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir/.templates" || exit 1
    local rc=0
    if ! tofu_init_strict "Azure"; then
        rc=$?
        cd - >/dev/null || exit 1
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
        return
    fi

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

    local test_dir
    test_dir=$(setup_test_dir)
    cmd_init --cloud-provider gcp --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir/.templates" || exit 1
    local rc=0
    if ! tofu_init_strict "GCP"; then
        rc=$?
        cd - >/dev/null || exit 1
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
        return
    fi

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

    local test_dir
    test_dir=$(setup_test_dir)
    cmd_init --cloud-provider hetzner --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir/.templates" || exit 1
    local rc=0
    if ! tofu_init_strict "Hetzner"; then
        rc=$?
        cd - >/dev/null || exit 1
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
        return
    fi

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

    local test_dir
    test_dir=$(setup_test_dir)
    cmd_init --cloud-provider digitalocean --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir/.templates" || exit 1
    local rc=0
    if ! tofu_init_strict "DigitalOcean"; then
        rc=$?
        cd - >/dev/null || exit 1
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
        return
    fi

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

    local test_dir
    test_dir=$(setup_test_dir)
    cmd_init --cloud-provider libvirt --deployment-dir "$test_dir" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir/.templates" || exit 1
    local rc=0
    if ! tofu_init_strict "Libvirt"; then
        rc=$?
        cd - >/dev/null || exit 1
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
        return
    fi

    if tofu validate >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Libvirt: tofu validate successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Libvirt: tofu validate failed"
    fi

    cd - >/dev/null
    cleanup_test_dir "$test_dir"
}
