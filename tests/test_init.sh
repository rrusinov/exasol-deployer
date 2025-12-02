#!/usr/bin/env bash
# Unit tests for lib/cmd_init.sh (multi-cloud support)

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

# Source the libraries we're testing
LIB_DIR="$TEST_DIR/../lib"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/versions.sh"
source "$LIB_DIR/cmd_init.sh"

echo "Testing cmd_init.sh multi-cloud functions"
echo "========================================="

# Provide a dummy DigitalOcean token so provider checks can run without real creds.
export DIGITALOCEAN_TOKEN="${DIGITALOCEAN_TOKEN:-DUMMY_TOKEN}"

# Test: Cloud provider validation
test_cloud_provider_validation() {
    echo ""
    echo "Test: Cloud provider validation"

    local test_dir=$(setup_test_dir)

    # Test with missing cloud provider
    if cmd_init --deployment-dir "$test_dir" ; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should fail without cloud provider"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should fail without cloud provider"
    fi

    # Test with invalid cloud provider
    if cmd_init --cloud-provider invalid --deployment-dir "$test_dir" ; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should fail with invalid cloud provider"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should fail with invalid cloud provider"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Valid cloud providers
test_valid_cloud_providers() {
    echo ""
    echo "Test: Valid cloud providers"

    local providers=("aws" "azure" "gcp" "hetzner" "digitalocean")

    for provider in "${providers[@]}"; do
        local test_dir=$(setup_test_dir)
        local args=(--cloud-provider "$provider" --deployment-dir "$test_dir")

        if [[ "$provider" == "azure" ]]; then
            local dummy_creds="$test_dir/azure.json"
            echo '{"appId":"a","password":"p","tenant":"t"}' > "$dummy_creds"
            args+=(--azure-subscription "dummy-sub" --azure-credentials-file "$dummy_creds")
        elif [[ "$provider" == "gcp" ]]; then
            args+=(--gcp-project "dummy-project")
        elif [[ "$provider" == "hetzner" ]]; then
            args+=(--hetzner-token "dummy-token")
        fi

        # Initialize with valid provider
        local output
        if output=$(cmd_init "${args[@]}" 2>&1); then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Should accept valid provider: $provider"

            # Check that state file contains cloud provider
            local cloud_from_state
            cloud_from_state=$(jq -r '.cloud_provider' "$test_dir/.exasol.json")
            if [[ "$cloud_from_state" == "$provider" ]]; then
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_PASSED=$((TESTS_PASSED + 1))
                echo -e "${GREEN}✓${NC} State file contains correct provider: $provider"
            else
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_FAILED=$((TESTS_FAILED + 1))
                echo -e "${RED}✗${NC} State file should contain provider: $provider (got: $cloud_from_state)"
            fi
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Should accept valid provider: $provider"
            echo "--- cmd_init output for provider $provider ---"
            echo "$output"
            echo "--------------------------------------------"
        fi

        cleanup_test_dir "$test_dir"
    done
}

# Test: AWS-specific initialization
test_aws_initialization() {
    echo ""
    echo "Test: AWS-specific initialization"

    local test_dir=$(setup_test_dir)

    # Initialize with AWS and spot instances
    cmd_init --cloud-provider aws \
        --deployment-dir "$test_dir" \
        --aws-region us-west-2 \
        --aws-spot-instance

    if [[ -f "$test_dir/variables.auto.tfvars" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should create variables.auto.tfvars"

        # Check for AWS-specific variables
        if grep -q "aws_region" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Variables file contains aws_region"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Variables file should contain aws_region"
        fi

        if grep -q "enable_spot_instances = true" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Variables file contains enable_spot_instances = true"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Variables file should contain enable_spot_instances = true"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should create variables.auto.tfvars"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Template directory selection
test_template_directory_selection() {
    echo ""
    echo "Test: Template directory selection"

    local test_dir=$(setup_test_dir)

    # Initialize with AWS (uses default templates/terraform/)
    cmd_init --cloud-provider aws --deployment-dir "$test_dir"

    if [[ -f "$test_dir/.templates/main.tf" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should copy templates for AWS"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should copy templates for AWS"
    fi

    cleanup_test_dir "$test_dir"
}

test_inventory_cloud_provider() {
    echo ""
    echo "Test: Inventory includes cloud provider"

    local test_dir=$(setup_test_dir)

    cmd_init --cloud-provider aws --deployment-dir "$test_dir" --aws-region us-east-1

    local inventory_template="$test_dir/.templates/inventory.tftpl"
    if [[ -f "$inventory_template" ]] && grep -q "cloud_provider=" "$inventory_template"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Inventory template contains cloud_provider host var"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Inventory template should include cloud_provider"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Credentials file includes cloud provider
test_credentials_file() {
    echo ""
    echo "Test: Credentials file includes cloud provider"

    local test_dir=$(setup_test_dir)
    local creds_file="$test_dir/azure_credentials.json"

    # Create dummy Azure credentials file for the test
    cat > "$creds_file" <<'EOF'
{
  "appId": "dummy-app-id",
  "password": "dummy-password",
  "tenant": "dummy-tenant",
  "subscriptionId": "dummy-subscription"
}
EOF

    cmd_init --cloud-provider azure --deployment-dir "$test_dir" --azure-credentials-file "$creds_file"

    if [[ -f "$test_dir/.credentials.json" ]]; then
        local cloud_provider
        cloud_provider=$(jq -r '.cloud_provider' "$test_dir/.credentials.json")

        if [[ "$cloud_provider" == "azure" ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Credentials file contains cloud_provider"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Credentials file should contain cloud_provider: azure (got: $cloud_provider)"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should create .credentials.json"
    fi

    cleanup_test_dir "$test_dir"
}

test_host_password_generation_and_override() {
    echo ""
    echo "Test: Host password generation and override"

    local test_dir
    test_dir=$(setup_test_dir)

    cmd_init --cloud-provider aws --deployment-dir "$test_dir" --aws-region us-east-1

    local generated_password
    generated_password=$(jq -r '.host_password' "$test_dir/.credentials.json")

    assert_equals "16" "${#generated_password}" "Generated host_password should use default length"
    assert_contains "$(cat "$test_dir/variables.auto.tfvars")" "host_password = \"$generated_password\"" "TF vars should include generated host_password"

    cleanup_test_dir "$test_dir"

    test_dir=$(setup_test_dir)
    local custom_password="MyHostPass1234"

    cmd_init --cloud-provider aws --deployment-dir "$test_dir" --aws-region us-east-1 --host-password "$custom_password"

    local stored_password
    stored_password=$(jq -r '.host_password' "$test_dir/.credentials.json")

    assert_equals "$custom_password" "$stored_password" "Custom host_password should be preserved"
    assert_contains "$(cat "$test_dir/variables.auto.tfvars")" "host_password = \"$custom_password\"" "TF vars should include custom host_password"

    cleanup_test_dir "$test_dir"
}

test_azure_credentials_file_usage() {
    echo ""
    echo "Test: Azure credentials file is written to tfvars"

    local test_dir
    test_dir=$(setup_test_dir)
    local creds_file="$test_dir/azure_credentials.json"
    cat > "$creds_file" <<'EOF'
{
  "appId": "app-id-123",
  "password": "secret-abc",
  "tenant": "tenant-xyz",
  "subscriptionId": "sub-123"
}
EOF

    cmd_init --cloud-provider azure \
        --deployment-dir "$test_dir" \
        --azure-credentials-file "$creds_file"

    if [[ -f "$test_dir/variables.auto.tfvars" ]]; then
        if grep -q 'azure_client_id = "app-id-123"' "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} variables.auto.tfvars contains azure_client_id"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} variables.auto.tfvars should contain azure_client_id"
        fi

        if grep -q 'azure_client_secret = "secret-abc"' "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} variables.auto.tfvars contains azure_client_secret"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} variables.auto.tfvars should contain azure_client_secret"
        fi

        if grep -q 'azure_tenant_id = "tenant-xyz"' "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} variables.auto.tfvars contains azure_tenant_id"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} variables.auto.tfvars should contain azure_tenant_id"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should create variables.auto.tfvars for Azure"
    fi

    cleanup_test_dir "$test_dir"
}

test_exasol_entrypoint_init_providers() {
    echo ""
    echo "Test: exasol entrypoint init works for all providers"

    local providers=("aws" "azure" "gcp" "hetzner" "digitalocean" "libvirt")

    for provider in "${providers[@]}"; do
        local test_dir
        test_dir=$(setup_test_dir)

        local init_cmd
        if [[ "$provider" == "libvirt" ]]; then
            init_cmd=("$TEST_DIR/../exasol" init --cloud-provider "$provider" --deployment-dir "$test_dir" --libvirt-uri qemu:///system)
        elif [[ "$provider" == "azure" ]]; then
            local dummy_creds="$test_dir/azure.json"
            echo '{"appId":"a","password":"p","tenant":"t"}' > "$dummy_creds"
            init_cmd=("$TEST_DIR/../exasol" init --cloud-provider "$provider" --deployment-dir "$test_dir" --azure-subscription "dummy-sub" --azure-credentials-file "$dummy_creds")
        elif [[ "$provider" == "gcp" ]]; then
            init_cmd=("$TEST_DIR/../exasol" init --cloud-provider "$provider" --deployment-dir "$test_dir" --gcp-project "dummy-project")
        elif [[ "$provider" == "hetzner" ]]; then
            init_cmd=("$TEST_DIR/../exasol" init --cloud-provider "$provider" --deployment-dir "$test_dir" --hetzner-token "dummy-token")
        else
            init_cmd=("$TEST_DIR/../exasol" init --cloud-provider "$provider" --deployment-dir "$test_dir")
        fi

        if "${init_cmd[@]}" ; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} exasol init should succeed for provider: $provider"

            local cloud_from_state
            cloud_from_state=$(jq -r '.cloud_provider' "$test_dir/.exasol.json")
            if [[ "$cloud_from_state" == "$provider" ]]; then
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_PASSED=$((TESTS_PASSED + 1))
                echo -e "${GREEN}✓${NC} State file records provider via entrypoint: $provider"
            else
                TESTS_TOTAL=$((TESTS_TOTAL + 1))
                TESTS_FAILED=$((TESTS_FAILED + 1))
                echo -e "${RED}✗${NC} State file should contain provider: $provider (got: $cloud_from_state)"
            fi
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} exasol init should succeed for provider: $provider"
        fi

        cleanup_test_dir "$test_dir"
    done
}

test_list_providers_shows_capabilities() {
    echo ""
    echo "Test: --list-providers shows capabilities"

    local output
    output=$(cmd_init --list-providers 2>&1)

    assert_contains "$output" "aws" "List should include aws"
    assert_contains "$output" "[✓] tofu power control" "List should mention infra power control"
    assert_contains "$output" "hetzner" "List should include hetzner"
    assert_contains "$output" "manual power-on (in-guest shutdown)" "List should mention manual power-on for unsupported providers"
}

# Test: README generation includes cloud provider
test_readme_generation() {
    echo ""
    echo "Test: README generation includes cloud provider"

    local test_dir=$(setup_test_dir)

    cmd_init --cloud-provider gcp --deployment-dir "$test_dir" --gcp-project "test-project-123"

    if [[ -f "$test_dir/README.md" ]]; then
        if grep -q "Google Cloud Platform" "$test_dir/README.md"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} README contains cloud provider name"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} README should contain cloud provider name"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should create README.md"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Data volumes per node option
test_data_volumes_per_node() {
    echo ""
    echo "Test: Data volumes per node option"

    local test_dir=$(setup_test_dir)

    # Initialize with custom data volumes per node
    cmd_init --cloud-provider aws \
        --deployment-dir "$test_dir" \
        --data-volumes-per-node 3 \
        --aws-region us-east-1 \
        --instance-type t3a.large \
        --db-password testpass \
        --adminui-password testpass \
        --cluster-size 1 \
        --data-volume-size 100 \
        --db-version exasol-2025.1.4 \
        --owner testuser

    if [[ -f "$test_dir/variables.auto.tfvars" ]]; then
        if grep -q "data_volumes_per_node = 3" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Variables file contains data_volumes_per_node = 3"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Variables file should contain data_volumes_per_node = 3"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should create variables.auto.tfvars"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Root volume size option
test_root_volume_size() {
    echo ""
    echo "Test: Root volume size option"

    local test_dir=$(setup_test_dir)

    # Initialize with custom root volume size
    cmd_init --cloud-provider aws \
        --deployment-dir "$test_dir" \
        --root-volume-size 100 \
        --aws-region us-east-1

    if [[ -f "$test_dir/variables.auto.tfvars" ]]; then
        if grep -q "root_volume_size = 100" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Variables file contains root_volume_size = 100"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Variables file should contain root_volume_size = 100"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should create variables.auto.tfvars"
    fi

    cleanup_test_dir "$test_dir"
}

# Test: Hetzner provider initialization
test_hetzner_initialization() {
    echo ""
    echo "Test: Hetzner provider initialization"

    local test_dir=$(setup_test_dir)

    # Initialize with Hetzner
    cmd_init --cloud-provider hetzner \
        --deployment-dir "$test_dir" \
        --hetzner-location fsn1

    if [[ -f "$test_dir/variables.auto.tfvars" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should create variables.auto.tfvars for Hetzner"

        # Check for Hetzner-specific variables
        if grep -q "hetzner_location" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Variables file contains hetzner_location"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Variables file should contain hetzner_location"
        fi

        # Check that Hetzner templates were copied
        if [[ -f "$test_dir/.templates/main.tf" ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Should copy templates for Hetzner"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Should copy templates for Hetzner"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should create variables.auto.tfvars for Hetzner"
    fi

    cleanup_test_dir "$test_dir"
}

test_hetzner_network_zone_configuration() {
    echo ""
    echo "Test: Hetzner network zone configuration"

    local default_dir
    default_dir=$(setup_test_dir)

    cmd_init --cloud-provider hetzner --deployment-dir "$default_dir"

    if grep -q 'hetzner_network_zone = "eu-central"' "$default_dir/variables.auto.tfvars"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Defaults hetzner_network_zone to eu-central"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should default hetzner_network_zone to eu-central"
    fi

    cleanup_test_dir "$default_dir"

    local custom_dir
    custom_dir=$(setup_test_dir)

    cmd_init --cloud-provider hetzner \
        --deployment-dir "$custom_dir" \
        --hetzner-network-zone us-east \
        --hetzner-location ash

    if grep -q 'hetzner_network_zone = "us-east"' "$custom_dir/variables.auto.tfvars"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Honors custom hetzner_network_zone flag"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Variables file should contain custom hetzner_network_zone"
    fi

    cleanup_test_dir "$custom_dir"
}

# Test: DigitalOcean provider initialization
test_digitalocean_initialization() {
    echo ""
    echo "Test: DigitalOcean provider initialization"

    local test_dir=$(setup_test_dir)

    # Initialize with DigitalOcean
    cmd_init --cloud-provider digitalocean \
        --deployment-dir "$test_dir" \
        --digitalocean-region nyc3 \
        --digitalocean-token "dummy-token-for-testing-12345"

    if [[ -f "$test_dir/variables.auto.tfvars" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should create variables.auto.tfvars for DigitalOcean"

        # Check for DigitalOcean-specific variables
        if grep -q "digitalocean_region" "$test_dir/variables.auto.tfvars"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Variables file contains digitalocean_region"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Variables file should contain digitalocean_region"
        fi

        # Check that DigitalOcean templates were copied
        if [[ -f "$test_dir/.templates/main.tf" ]]; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} Should copy templates for DigitalOcean"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} Should copy templates for DigitalOcean"
        fi
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should create variables.auto.tfvars for DigitalOcean"
    fi

    cleanup_test_dir "$test_dir"
}

test_digitalocean_arm64_guard() {
    echo ""
    echo "Test: DigitalOcean rejects arm64 architectures"

    local test_dir
    test_dir=$(setup_test_dir)
    local versions_override="$test_dir/versions.conf"

    cat > "$versions_override" <<'EOF'
[exasol-2099.1.1-arm64]
ARCHITECTURE=arm64
DB_VERSION=@exasol-2099.1.1~linux-arm64
DB_DOWNLOAD_URL=https://example.com/exasol-2099.1.1-arm64.tar.gz
DB_CHECKSUM=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
C4_VERSION=4.28.4
C4_DOWNLOAD_URL=https://example.com/c4-arm64
C4_CHECKSUM=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
DEFAULT_INSTANCE_TYPE=c-2

[default]
VERSION=exasol-2099.1.1-arm64
EOF

    local previous_versions_config="${EXASOL_VERSIONS_CONFIG:-}"
    EXASOL_VERSIONS_CONFIG="$versions_override"

    local output
    output=$(cmd_init \
        --cloud-provider digitalocean \
        --deployment-dir "$test_dir" \
        --db-version exasol-2099.1.1-arm64 2>&1)
    local exit_code=$?

    if [[ -n "$previous_versions_config" ]]; then
        EXASOL_VERSIONS_CONFIG="$previous_versions_config"
    else
        unset EXASOL_VERSIONS_CONFIG
    fi

    assert_failure "$exit_code" "DigitalOcean arm64 init should fail"
    assert_contains "$output" "support only x86_64" "Error should mention architecture limitation"

    cleanup_test_dir "$test_dir"
}

test_digitalocean_token_validation() {
    echo ""
    echo "Test: DigitalOcean token validation"

    # Temporarily enforce provider checks for this block and unset dummy token
    local prev_skip="${EXASOL_SKIP_PROVIDER_CHECKS:-}"
    local prev_do_token="${DIGITALOCEAN_TOKEN:-}"
    unset EXASOL_SKIP_PROVIDER_CHECKS
    unset DIGITALOCEAN_TOKEN

    # Simulate different home directory to avoid modifying real ~/.digitalocean_token
    local original_home="$HOME"
    local temp_home=$(mktemp -d)
    export HOME="$temp_home"

    # Test 1: Init without token should fail
    echo "  Testing: Init without token should fail"
    local output
    local test_dir_missing_token
    test_dir_missing_token=$(setup_test_dir)
    output=$(cmd_init --cloud-provider digitalocean \
        --deployment-dir "$test_dir_missing_token" \
        --digitalocean-region nyc3 \
        2>&1)
    local exit_code=$?

    assert_failure "$exit_code" "DigitalOcean init without token should fail"
    assert_contains "$output" "DigitalOcean token is required" "Error should mention token requirement"

    # Test 2: Init with empty token should fail
    echo "  Testing: Init with empty token should fail"
    local test_dir2=$(setup_test_dir)
    output=$(cmd_init --cloud-provider digitalocean \
        --deployment-dir "$test_dir2" \
        --digitalocean-region nyc3 \
        --digitalocean-token "" \
        2>&1)
    exit_code=$?

    cleanup_test_dir "$test_dir2"

    assert_failure "$exit_code" "DigitalOcean init with empty token should fail"
    assert_contains "$output" "DigitalOcean token" "Error should mention token"

    # Test 3: Init with token from file should succeed
    echo "  Testing: Init with token from ~/.digitalocean_token should succeed"
    echo "test-token-from-file-12345" > "$HOME/.digitalocean_token"

    local test_dir_success
    test_dir_success=$(setup_test_dir)
    output=$(cmd_init --cloud-provider digitalocean \
        --deployment-dir "$test_dir_success" \
        --digitalocean-region nyc3 \
        2>&1)
    exit_code=$?

    assert_success "$exit_code" "DigitalOcean init with token from file should succeed"

    # Restore original home
    export HOME="$original_home"
    rm -rf "$temp_home"

    cleanup_test_dir "$test_dir_missing_token"
    cleanup_test_dir "$test_dir_success"

    # Restore env flags
    if [[ -n "$prev_skip" ]]; then
        EXASOL_SKIP_PROVIDER_CHECKS="$prev_skip"
    else
        unset EXASOL_SKIP_PROVIDER_CHECKS
    fi
    if [[ -n "$prev_do_token" ]]; then
        export DIGITALOCEAN_TOKEN="$prev_do_token"
    else
        unset DIGITALOCEAN_TOKEN
    fi
}

test_hetzner_private_ip_template() {
    echo ""
    echo "Test: Hetzner template uses network private IPs"

    local template_file="$TEST_DIR/../templates/terraform-hetzner/main.tf"
    if [[ ! -f "$template_file" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Template file missing: $template_file"
        return
    fi

    if grep -q "node_private_ips = local.overlay_network_ips" "$template_file"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Hetzner node_private_ips use multicast overlay"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Hetzner node_private_ips should use multicast overlay IPs"
    fi
}

test_config_datadisk_format() {
    echo ""
    echo "Test: Config template uses comma-separated disks"

    local config_template="$TEST_DIR/../templates/ansible/config.j2"
    if grep -q 'CCC_HOST_DATADISK="{{ data_disk_paths_var }}"' "$config_template"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Config template wraps data disks in quotes"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Config template should quote data disks"
    fi

    local playbook="$TEST_DIR/../templates/ansible/setup-exasol-cluster.yml"
    if grep -q 'data_disk_paths: "{{ exasol_symlinks.stdout_lines }}' "$playbook"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} data_disk_paths stored as list"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} data_disk_paths should remain a list"
    fi

    if grep -q 'data_disk_paths_var: "{{ data_disk_paths | join' "$playbook" && \
       grep -q "join(',')" "$playbook"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Template joins data disks with commas"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Template should join data disks with commas"
    fi
}

# Test: GCP zone configuration
test_gcp_zone_configuration() {
    echo ""
    echo "Test: GCP zone configuration"

    local default_dir
    default_dir=$(setup_test_dir)

    cmd_init --cloud-provider gcp --deployment-dir "$default_dir" --gcp-project "test-project-123"

    if grep -q 'gcp_zone = "us-central1-a"' "$default_dir/variables.auto.tfvars"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Defaults to <region>-a when zone not specified"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should default gcp_zone to us-central1-a"
    fi

    cleanup_test_dir "$default_dir"

    local custom_dir
    custom_dir=$(setup_test_dir)

    cmd_init --cloud-provider gcp \
        --deployment-dir "$custom_dir" \
        --gcp-region europe-west3 \
        --gcp-zone europe-west3-b \
        --gcp-project "test-project-123"

    if grep -q 'gcp_zone = "europe-west3-b"' "$custom_dir/variables.auto.tfvars"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Honors custom gcp_zone flag"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Variables file should contain custom gcp_zone"
    fi

    cleanup_test_dir "$custom_dir"
}

# Test: Azure subscription ID precedence
test_azure_subscription_precedence() {
    echo ""
    echo "Test: Azure subscription ID precedence"

    local test_dir
    test_dir=$(setup_test_dir)
    local creds_file="$test_dir/azure_creds_full.json"
    
    # Create creds file with subscriptionId
    cat > "$creds_file" <<EOF
{
  "appId": "app-id",
  "password": "pass",
  "tenant": "tenant",
  "subscriptionId": "sub-from-file"
}
EOF

    # 1. Fail if missing
    local simple_creds="$test_dir/simple.json"
    echo '{"appId":"a","password":"p","tenant":"t"}' > "$simple_creds"
    
    unset AZURE_SUBSCRIPTION_ID
    local output
    if output=$(cmd_init --cloud-provider azure --deployment-dir "$test_dir/fail" --azure-credentials-file "$simple_creds" 2>&1); then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should fail without any subscription ID"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Fails without subscription ID"
        echo "--- cmd_init output (expected failure) ---"
        echo "$output"
        echo "-----------------------------------------"
    fi

    # 2. File Precedence (Flag=Empty, Env=Empty)
    unset AZURE_SUBSCRIPTION_ID
    cmd_init --cloud-provider azure --deployment-dir "$test_dir/file" --azure-credentials-file "$creds_file"
    if grep -q 'azure_subscription = "sub-from-file"' "$test_dir/file/variables.auto.tfvars"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Uses subscription from file"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should use subscription from file"
    fi

    # 3. Env Precedence (Flag=Empty, Env=Set, File=Set)
    export AZURE_SUBSCRIPTION_ID="sub-from-env"
    cmd_init --cloud-provider azure --deployment-dir "$test_dir/env" --azure-credentials-file "$creds_file"
    if grep -q 'azure_subscription = "sub-from-env"' "$test_dir/env/variables.auto.tfvars"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Uses subscription from env var"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should use subscription from env var"
    fi

    # 4. Flag Precedence (Flag=Set, Env=Set, File=Set)
    cmd_init --cloud-provider azure --deployment-dir "$test_dir/flag" --azure-credentials-file "$creds_file" --azure-subscription "sub-from-flag"
    if grep -q 'azure_subscription = "sub-from-flag"' "$test_dir/flag/variables.auto.tfvars"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Uses subscription from flag"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should use subscription from flag"
    fi

    # Cleanup
    unset AZURE_SUBSCRIPTION_ID
    cleanup_test_dir "$test_dir"
}

# Run all tests
test_cloud_provider_validation
test_valid_cloud_providers
test_aws_initialization
test_template_directory_selection
test_inventory_cloud_provider
test_credentials_file
test_host_password_generation_and_override
test_azure_credentials_file_usage
test_azure_subscription_precedence
test_list_providers_shows_capabilities
test_readme_generation
test_data_volumes_per_node
test_root_volume_size
test_gcp_zone_configuration
test_hetzner_initialization
test_hetzner_network_zone_configuration
test_digitalocean_initialization
test_digitalocean_arm64_guard
test_digitalocean_token_validation
test_hetzner_private_ip_template
test_config_datadisk_format
test_exasol_entrypoint_init_providers

# Show summary
test_summary
