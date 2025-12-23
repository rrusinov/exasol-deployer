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

    cd "$test_dir" || exit 1
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

    # Create dummy Azure credentials for template validation (outside deploy dir)
    local creds_file
    creds_file=$(mktemp "/tmp/azure_test_creds-XXXXXX.json")
    cat > "$creds_file" << 'EOF'
{
  "appId": "test-app-id",
  "password": "test-password",
  "tenant": "test-tenant",
  "subscriptionId": "test-subscription-id"
}
EOF
    cmd_init --cloud-provider azure --deployment-dir "$test_dir" --azure-credentials-file "$creds_file" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        rm -f "$creds_file"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir" || exit 1
    local rc=0
    if ! tofu_init_strict "Azure"; then
        rc=$?
        cd - >/dev/null || exit 1
        rm -f "$creds_file"
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
    rm -f "$creds_file"
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

    # Create dummy GCP credentials for template validation (outside deploy dir)
    local creds_file
    creds_file=$(mktemp "/tmp/gcp_test_creds-XXXXXX.json")
    cat > "$creds_file" << 'EOF'
{
  "type": "service_account",
  "project_id": "test-project-123",
  "private_key_id": "test-key-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\ntest-private-key\n-----END PRIVATE KEY-----\n",
  "client_email": "test@test-project-123.iam.gserviceaccount.com",
  "client_id": "123456789",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/test%40test-project-123.iam.gserviceaccount.com"
}
EOF

    cmd_init --cloud-provider gcp --deployment-dir "$test_dir" --gcp-credentials-file "$creds_file" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        rm -f "$creds_file"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir" || exit 1
    local rc=0
    if ! tofu_init_strict "GCP"; then
        rc=$?
        cd - >/dev/null || exit 1
        rm -f "$creds_file"
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
    rm -f "$creds_file"
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

    cd "$test_dir" || exit 1
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
    cmd_init --cloud-provider digitalocean --deployment-dir "$test_dir" --digitalocean-token "dummy-token-for-testing-12345" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir" || exit 1
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

# Test: Exoscale template validation
test_exoscale_template_validation() {
    echo ""
    echo "Test: Exoscale template validation"

    if ! command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (tofu not available)"
        return
    fi

    local test_dir
    test_dir=$(setup_test_dir)
    cmd_init --cloud-provider exoscale --deployment-dir "$test_dir" --exoscale-api-key "EXOdummy-key-12345" --exoscale-api-secret "dummy-secret-for-testing" 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir" || exit 1
    local rc=0
    if ! tofu_init_strict "Exoscale"; then
        rc=$?
        cd - >/dev/null || exit 1
        cleanup_test_dir "$test_dir"
        [[ $rc -eq 2 ]] && return 0
        return
    fi

    if tofu validate >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Exoscale: tofu validate successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Exoscale: tofu validate failed"
    fi

    cd - >/dev/null
    cleanup_test_dir "$test_dir"
}

# Test: OCI template validation
test_oci_template_validation() {
    echo ""
    echo "Test: OCI template validation"

    if ! command -v tofu >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping (tofu not available)"
        return
    fi

    local test_dir
    test_dir=$(setup_test_dir)
    cmd_init --cloud-provider oci --deployment-dir "$test_dir" --oci-compartment-ocid "ocid1.compartment.oc1..test" 2>/dev/null

    cd "$test_dir" || exit 1

    if ! tofu init >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} OCI: tofu init failed"
        cd - >/dev/null
        cleanup_test_dir "$test_dir"
        return
    fi

    if tofu validate >/dev/null 2>&1; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} OCI: tofu validate successful"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} OCI: tofu validate failed"
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
    cmd_init --cloud-provider libvirt --deployment-dir "$test_dir" --libvirt-uri qemu:///system 2>/dev/null

    if [[ ! -d "$test_dir/.templates" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Templates directory not created"
        cleanup_test_dir "$test_dir"
        return
    fi

    cd "$test_dir" || exit 1
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
