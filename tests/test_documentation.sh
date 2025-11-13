#!/usr/bin/env bash
# Unit tests for documentation validation
# Ensures that README and --help outputs match the actual supported options

# Get script directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

source "$TEST_DIR/test_helper.sh"

# Source the command libraries to get supported options
source "$SCRIPT_ROOT/lib/cmd_init.sh"

echo "Testing documentation consistency"
echo "=================================="

# Test: Verify supported cloud providers match in code and documentation
test_cloud_providers_documented() {
    echo ""
    echo "Test: Cloud providers documented correctly"

    # Extract providers from code (lib/cmd_init.sh)
    local providers_in_code=("aws" "azure" "gcp" "hetzner" "digitalocean")

    # Check README mentions all providers
    local readme_file="$SCRIPT_ROOT/README.md"
    local all_found=true

    for provider in "${providers_in_code[@]}"; do
        if ! grep -q "$provider" "$readme_file"; then
            echo -e "${RED}✗${NC} Provider $provider not found in README"
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            all_found=false
        fi
    done

    if $all_found; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} All cloud providers documented in README"
    fi

    # Check cloud setup docs exist
    local cloud_docs=(
        "$SCRIPT_ROOT/docs/CLOUD_SETUP.md"
        "$SCRIPT_ROOT/docs/CLOUD_SETUP_AWS.md"
        "$SCRIPT_ROOT/docs/CLOUD_SETUP_AZURE.md"
        "$SCRIPT_ROOT/docs/CLOUD_SETUP_GCP.md"
        "$SCRIPT_ROOT/docs/CLOUD_SETUP_HETZNER.md"
        "$SCRIPT_ROOT/docs/CLOUD_SETUP_DIGITALOCEAN.md"
    )

    for doc in "${cloud_docs[@]}"; do
        assert_file_exists "$doc" "Cloud setup doc should exist: $(basename "$doc")"
    done
}

# Test: Verify init command help matches supported options
test_init_help_matches_code() {
    echo ""
    echo "Test: Init command help matches code"

    # Get help output
    local help_output
    help_output=$("$SCRIPT_ROOT/exasol" init --help 2>&1)

    # Check for required options
    local required_options=(
        "--cloud-provider"
        "--deployment-dir"
        "--db-version"
        "--list-versions"
        "--list-providers"
        "--cluster-size"
        "--instance-type"
        "--data-volume-size"
        "--data-volumes-per-node"
        "--root-volume-size"
        "--db-password"
        "--adminui-password"
        "--owner"
        "--allowed-cidr"
    )

    for option in "${required_options[@]}"; do
        assert_contains "$help_output" "$option" "Help should document option: $option"
    done

    # Check for AWS options
    local aws_options=(
        "--aws-region"
        "--aws-profile"
        "--aws-spot-instance"
    )

    for option in "${aws_options[@]}"; do
        assert_contains "$help_output" "$option" "Help should document AWS option: $option"
    done

    # Check for Azure options
    local azure_options=(
        "--azure-region"
        "--azure-subscription"
        "--azure-spot-instance"
    )

    for option in "${azure_options[@]}"; do
        assert_contains "$help_output" "$option" "Help should document Azure option: $option"
    done

    # Check for GCP options
    local gcp_options=(
        "--gcp-region"
        "--gcp-project"
        "--gcp-spot-instance"
    )

    for option in "${gcp_options[@]}"; do
        assert_contains "$help_output" "$option" "Help should document GCP option: $option"
    done

    # Check for Hetzner options
    local hetzner_options=(
        "--hetzner-location"
        "--hetzner-token"
    )

    for option in "${hetzner_options[@]}"; do
        assert_contains "$help_output" "$option" "Help should document Hetzner option: $option"
    done

    # Check for DigitalOcean options
    local do_options=(
        "--digitalocean-region"
        "--digitalocean-token"
    )

    for option in "${do_options[@]}"; do
        assert_contains "$help_output" "$option" "Help should document DigitalOcean option: $option"
    done
}

# Test: Verify deploy command help matches code
test_deploy_help_complete() {
    echo ""
    echo "Test: Deploy command help is complete"

    local help_output
    help_output=$("$SCRIPT_ROOT/exasol" deploy --help 2>&1)

    assert_contains "$help_output" "--deployment-dir" "Deploy help should document --deployment-dir"
    assert_contains "$help_output" "Usage:" "Deploy help should have usage section"
    assert_contains "$help_output" "Example:" "Deploy help should have examples"
}

# Test: Verify destroy command help matches code
test_destroy_help_complete() {
    echo ""
    echo "Test: Destroy command help is complete"

    local help_output
    help_output=$("$SCRIPT_ROOT/exasol" destroy --help 2>&1)

    assert_contains "$help_output" "--deployment-dir" "Destroy help should document --deployment-dir"
    assert_contains "$help_output" "--auto-approve" "Destroy help should document --auto-approve"
    assert_contains "$help_output" "Usage:" "Destroy help should have usage section"
    assert_contains "$help_output" "Examples:" "Destroy help should have examples"
}

# Test: Verify status command help matches code
test_status_help_complete() {
    echo ""
    echo "Test: Status command help is complete"

    local help_output
    help_output=$("$SCRIPT_ROOT/exasol" status --help 2>&1)

    assert_contains "$help_output" "Usage:" "Status help should have usage section"
    assert_contains "$help_output" "Examples:" "Status help should have examples"
}

# Test: Verify main help shows all commands
test_main_help_complete() {
    echo ""
    echo "Test: Main help shows all commands"

    local help_output
    help_output=$("$SCRIPT_ROOT/exasol" --help 2>&1)

    local commands=(
        "init"
        "deploy"
        "destroy"
        "status"
        "version"
        "help"
    )

    for cmd in "${commands[@]}"; do
        assert_contains "$help_output" "$cmd" "Main help should list command: $cmd"
    done

    # Check for global flags
    assert_contains "$help_output" "--deployment-dir" "Main help should document --deployment-dir"
    assert_contains "$help_output" "--log-level" "Main help should document --log-level"
}

# Test: Verify README documents all init options
test_readme_documents_init_options() {
    echo ""
    echo "Test: README documents init command options"

    local readme_file="$SCRIPT_ROOT/README.md"

    # Key options that should be documented
    local key_options=(
        "cloud-provider"
        "deployment-dir"
        "db-version"
        "cluster-size"
        "instance-type"
        "data-volume-size"
        "aws-region"
        "azure-region"
        "gcp-region"
        "hetzner-location"
        "digitalocean-region"
        "spot-instance"
    )

    for option in "${key_options[@]}"; do
        if grep -q "$option" "$readme_file"; then
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
            echo -e "${GREEN}✓${NC} README documents option: $option"
        else
            TESTS_TOTAL=$((TESTS_TOTAL + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "${RED}✗${NC} README missing option: $option"
        fi
    done
}

# Test: Verify cloud setup docs mention required authentication
test_cloud_docs_mention_auth() {
    echo ""
    echo "Test: Cloud setup docs mention authentication"

    # Check AWS doc
    local aws_doc="$SCRIPT_ROOT/docs/CLOUD_SETUP_AWS.md"
    if [[ -f "$aws_doc" ]]; then
        assert_contains "$(cat "$aws_doc")" "credentials" "AWS doc should mention credentials"
        assert_contains "$(cat "$aws_doc")" "IAM" "AWS doc should mention IAM"
    fi

    # Check Azure doc
    local azure_doc="$SCRIPT_ROOT/docs/CLOUD_SETUP_AZURE.md"
    if [[ -f "$azure_doc" ]]; then
        assert_contains "$(cat "$azure_doc")" "az login" "Azure doc should mention az login"
        assert_contains "$(cat "$azure_doc")" "subscription" "Azure doc should mention subscription"
    fi

    # Check GCP doc
    local gcp_doc="$SCRIPT_ROOT/docs/CLOUD_SETUP_GCP.md"
    if [[ -f "$gcp_doc" ]]; then
        assert_contains "$(cat "$gcp_doc")" "gcloud" "GCP doc should mention gcloud"
        assert_contains "$(cat "$gcp_doc")" "project" "GCP doc should mention project"
    fi

    # Check Hetzner doc
    local hetzner_doc="$SCRIPT_ROOT/docs/CLOUD_SETUP_HETZNER.md"
    if [[ -f "$hetzner_doc" ]]; then
        assert_contains "$(cat "$hetzner_doc")" "API token" "Hetzner doc should mention API token"
    fi

    # Check DigitalOcean doc
    local do_doc="$SCRIPT_ROOT/docs/CLOUD_SETUP_DIGITALOCEAN.md"
    if [[ -f "$do_doc" ]]; then
        assert_contains "$(cat "$do_doc")" "API token" "DigitalOcean doc should mention API token"
    fi
}

# Test: Verify default values consistency between code and docs
test_default_values_documented() {
    echo ""
    echo "Test: Default values documented correctly"

    # Check init help for defaults
    local help_output
    help_output=$("$SCRIPT_ROOT/exasol" init --help 2>&1)

    # Defaults that should be documented
    assert_contains "$help_output" "default: \"us-east-1\"" "AWS region default should be documented"
    assert_contains "$help_output" "default: \"eastus\"" "Azure region default should be documented"
    assert_contains "$help_output" "default: \"us-central1\"" "GCP region default should be documented"
    assert_contains "$help_output" "default: \"nbg1\"" "Hetzner location default should be documented"
    assert_contains "$help_output" "default: \"nyc3\"" "DigitalOcean region default should be documented"
    assert_contains "$help_output" "default: 1" "Cluster size default should be documented"
    assert_contains "$help_output" "default: 100" "Data volume size default should be documented"
    assert_contains "$help_output" "default: 1" "Data volumes per node default should be documented"
    assert_contains "$help_output" "default: 50" "Root volume size default should be documented"
}

# Test: Verify examples in help are valid
test_help_examples_valid() {
    echo ""
    echo "Test: Help examples use valid syntax"

    local help_output
    help_output=$("$SCRIPT_ROOT/exasol" init --help 2>&1)

    # Examples should use proper flags
    assert_contains "$help_output" "exasol init --cloud-provider" "Examples should use --cloud-provider flag"
    assert_contains "$help_output" "exasol init --list-providers" "Examples should show --list-providers"
    assert_contains "$help_output" "exasol init --list-versions" "Examples should show --list-versions"
}

# Test: Verify README links to cloud setup docs
test_readme_links_to_cloud_docs() {
    echo ""
    echo "Test: README links to cloud setup documentation"

    local readme_file="$SCRIPT_ROOT/README.md"
    local readme_content
    readme_content=$(cat "$readme_file")

    # Check for links to cloud setup docs
    assert_contains "$readme_content" "docs/CLOUD_SETUP.md" "README should link to cloud setup overview"
    assert_contains "$readme_content" "docs/CLOUD_SETUP_AWS.md" "README should link to AWS setup"
    assert_contains "$readme_content" "docs/CLOUD_SETUP_AZURE.md" "README should link to Azure setup"
    assert_contains "$readme_content" "docs/CLOUD_SETUP_GCP.md" "README should link to GCP setup"
    assert_contains "$readme_content" "docs/CLOUD_SETUP_HETZNER.md" "README should link to Hetzner setup"
    assert_contains "$readme_content" "docs/CLOUD_SETUP_DIGITALOCEAN.md" "README should link to DigitalOcean setup"
}

# Test: Verify cloud setup overview has all provider links
test_cloud_setup_overview_complete() {
    echo ""
    echo "Test: Cloud setup overview links to all providers"

    local overview_doc="$SCRIPT_ROOT/docs/CLOUD_SETUP.md"
    if [[ ! -f "$overview_doc" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} CLOUD_SETUP.md not found"
        return
    fi

    local overview_content
    overview_content=$(cat "$overview_doc")

    assert_contains "$overview_content" "CLOUD_SETUP_AWS.md" "Overview should link to AWS setup"
    assert_contains "$overview_content" "CLOUD_SETUP_AZURE.md" "Overview should link to Azure setup"
    assert_contains "$overview_content" "CLOUD_SETUP_GCP.md" "Overview should link to GCP setup"
    assert_contains "$overview_content" "CLOUD_SETUP_HETZNER.md" "Overview should link to Hetzner setup"
    assert_contains "$overview_content" "CLOUD_SETUP_DIGITALOCEAN.md" "Overview should link to DigitalOcean setup"
}

# Run all tests
test_cloud_providers_documented
test_init_help_matches_code
test_deploy_help_complete
test_destroy_help_complete
test_status_help_complete
test_main_help_complete
test_readme_documents_init_options
test_cloud_docs_mention_auth
test_default_values_documented
test_help_examples_valid
test_readme_links_to_cloud_docs
test_cloud_setup_overview_complete

# Print summary
test_summary
