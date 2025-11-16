#!/usr/bin/env bash
# Unit tests for lib/cmd_init.sh (multi-cloud support)

# Get script directory
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

# Test: Cloud provider validation
test_cloud_provider_validation() {
    echo ""
    echo "Test: Cloud provider validation"

    local test_dir=$(setup_test_dir)

    # Test with missing cloud provider
    if cmd_init --deployment-dir "$test_dir" 2>/dev/null; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Should fail without cloud provider"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Should fail without cloud provider"
    fi

    # Test with invalid cloud provider
    if cmd_init --cloud-provider invalid --deployment-dir "$test_dir" 2>/dev/null; then
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

        # Initialize with valid provider
        if cmd_init --cloud-provider "$provider" --deployment-dir "$test_dir" 2>/dev/null; then
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
        --aws-spot-instance \
        2>/dev/null

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
    cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null

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

    cmd_init --cloud-provider aws --deployment-dir "$test_dir" 2>/dev/null

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

    cmd_init --cloud-provider azure --deployment-dir "$test_dir" 2>/dev/null

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

    cmd_init --cloud-provider gcp --deployment-dir "$test_dir" 2>/dev/null

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
        2>/dev/null

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
        2>/dev/null

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
        --hetzner-location fsn1 \
        2>/dev/null

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

    cmd_init --cloud-provider hetzner --deployment-dir "$default_dir" 2>/dev/null

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
        --hetzner-location ash \
        2>/dev/null

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
        2>/dev/null

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

    if grep -q "node_private_ips = \\[for network in hcloud_server_network.exasol_node_network" "$template_file"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} Hetzner node_private_ips sourced from server network"
    else
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} Hetzner node_private_ips should read from hcloud_server_network.exasol_node_network"
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

    cmd_init --cloud-provider gcp --deployment-dir "$default_dir" 2>/dev/null

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
        2>/dev/null

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

# Run all tests
test_cloud_provider_validation
test_valid_cloud_providers
test_aws_initialization
test_template_directory_selection
test_inventory_cloud_provider
test_credentials_file
test_list_providers_shows_capabilities
test_readme_generation
test_data_volumes_per_node
test_root_volume_size
test_gcp_zone_configuration
test_hetzner_initialization
test_hetzner_network_zone_configuration
test_digitalocean_initialization
test_digitalocean_arm64_guard
test_hetzner_private_ip_template
test_config_datadisk_format

# Show summary
test_summary
