#!/usr/bin/env bash
# Test dependency installation feature

set -euo pipefail

# shellcheck disable=SC2155
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
# shellcheck source=./test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

# Simple fail function for test assertions
fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

check_network_connectivity() {
    local probe_url="${URL_AVAILABILITY_PROBE_URL:-https://example.com}"
    curl --head --silent --fail --location --max-time 5 "$probe_url" > /dev/null 2>&1
}

check_opentofu_availability() {
    local opentofu_url="https://github.com/opentofu/opentofu/releases/download/v1.10.7/tofu_1.10.7_linux_amd64.zip"
    curl --head --silent --fail --location --max-time 10 "$opentofu_url" > /dev/null 2>&1
}

test_dependency_installation() {
    local test_dir
    test_dir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$test_dir'" EXIT
    
    echo "Testing dependency installation in: $test_dir"
    
    # Build installer
    local installer="$PROJECT_ROOT/build/exasol-deployer.sh"
    if [[ ! -f "$installer" ]]; then
        echo "Building installer..."
        (cd "$PROJECT_ROOT" && ./scripts/create-release.sh >/dev/null 2>&1)
    fi
    
    # Test dependencies-only installation
    echo "Testing --dependencies-only installation..."
    # Temporarily restore UTF-8 locale for installer (Ansible needs it)
    # shellcheck disable=SC2030,SC2031
    (
        export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
        "$installer" --dependencies-only --prefix "$test_dir" --yes >/dev/null 2>&1
    )
    
    # Verify OpenTofu installation
    local tofu_binary="$test_dir/exasol-deployer/share/tofu/tofu"
    [[ -f "$tofu_binary" ]] || fail "OpenTofu binary not found: $tofu_binary"
    [[ -x "$tofu_binary" ]] || fail "OpenTofu binary not executable: $tofu_binary"
    
    # Test OpenTofu works
    local tofu_version
    tofu_version=$("$tofu_binary" version | head -1)
    [[ "$tofu_version" == *"OpenTofu"* ]] || fail "OpenTofu version check failed: $tofu_version"
    echo "✓ OpenTofu version: $tofu_version"
    
    # Verify Python installation
    local python_binary="$test_dir/exasol-deployer/share/python/bin/python3"
    [[ -f "$python_binary" ]] || fail "Python binary not found: $python_binary"
    [[ -x "$python_binary" ]] || fail "Python binary not executable: $python_binary"
    
    # Test Python works
    local python_version
    python_version=$("$python_binary" --version)
    [[ "$python_version" == *"Python 3.11"* ]] || fail "Python version check failed: $python_version"
    echo "✓ Python version: $python_version"
    
    # Verify jq installation
    local jq_binary="$test_dir/exasol-deployer/share/jq/jq"
    [[ -f "$jq_binary" ]] || fail "jq binary not found: $jq_binary"
    [[ -x "$jq_binary" ]] || fail "jq binary not executable: $jq_binary"
    
    # Test jq works
    local jq_version
    jq_version=$("$jq_binary" --version)
    [[ "$jq_version" == *"jq"* ]] || fail "jq version check failed: $jq_version"
    echo "✓ jq version: $jq_version"
    
    # Verify Ansible installation
    local ansible_binary="$test_dir/exasol-deployer/share/python/bin/ansible-playbook"
    [[ -f "$ansible_binary" ]] || fail "Ansible binary not found: $ansible_binary"
    [[ -x "$ansible_binary" ]] || fail "Ansible binary not executable: $ansible_binary"
    
    # Test Ansible works (with UTF-8 locale)
    local ansible_version
    # shellcheck disable=SC2030,SC2031
    ansible_version=$(
        export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
        "$ansible_binary" --version | head -1
    )
    [[ "$ansible_version" == *"ansible-playbook"* ]] || fail "Ansible version check failed: $ansible_version"
    echo "✓ Ansible version: $ansible_version"
    
    echo "✓ All dependency installation tests passed"
}

test_full_installation_with_dependencies() {
    local test_dir
    test_dir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$test_dir'" EXIT
    
    echo "Testing full installation with dependencies in: $test_dir"
    
    # Build installer
    local installer="$PROJECT_ROOT/build/exasol-deployer.sh"
    if [[ ! -f "$installer" ]]; then
        echo "Building installer..."
        (cd "$PROJECT_ROOT" && ./scripts/create-release.sh >/dev/null 2>&1)
    fi
    
    # Test full installation with dependencies
    echo "Testing --install-dependencies installation..."
    # Temporarily restore UTF-8 locale for installer (Ansible needs it)
    # shellcheck disable=SC2030,SC2031
    (
        export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
        "$installer" --install-dependencies --prefix "$test_dir" --yes --no-path >/dev/null 2>&1
    )
    
    # Verify main installation
    local exasol_binary="$test_dir/exasol"
    [[ -f "$exasol_binary" ]] || fail "Exasol binary not found: $exasol_binary"
    [[ -x "$exasol_binary" ]] || fail "Exasol binary not executable: $exasol_binary"
    
    # Test exasol works (should detect local dependencies)
    local exasol_version
    exasol_version=$("$exasol_binary" version)
    [[ "$exasol_version" == *"Exasol Cloud Deployer"* ]] || fail "Exasol version check failed: $exasol_version"
    echo "✓ Exasol version: $exasol_version"
    
    # Verify dependencies are installed
    [[ -f "$test_dir/exasol-deployer/share/tofu/tofu" ]] || fail "OpenTofu not installed"
    [[ -f "$test_dir/exasol-deployer/share/jq/jq" ]] || fail "jq not installed"
    [[ -f "$test_dir/exasol-deployer/share/python/bin/python3" ]] || fail "Python not installed"
    [[ -f "$test_dir/exasol-deployer/share/python/bin/ansible-playbook" ]] || fail "Ansible not installed"
    
    echo "✓ Full installation with dependencies test passed"
}

test_dependency_detection() {
    local test_dir
    test_dir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$test_dir'" EXIT
    
    echo "Testing dependency detection in: $test_dir"
    
    # Install with dependencies
    local installer="$PROJECT_ROOT/build/exasol-deployer.sh"
    # Temporarily restore UTF-8 locale for installer (Ansible needs it)
    # shellcheck disable=SC2030,SC2031
    (
        export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
        "$installer" --install-dependencies --prefix "$test_dir" --yes --no-path >/dev/null 2>&1
    )
    
    # Test that exasol detects and uses local dependencies
    local exasol_binary="$test_dir/exasol"
    
    # The help command should work (requires dependency detection)
    local help_output
    help_output=$("$exasol_binary" help 2>&1 | head -5)
    [[ "$help_output" == *"Usage:"* ]] || fail "Help command failed: $help_output"
    
    echo "✓ Dependency detection test passed"
}

# Run tests
main() {
    echo "Starting dependency installation tests..."
    
    if ! check_network_connectivity; then
        echo ""
        echo -e "${YELLOW}⊘${NC} Skipping dependency installation tests (no outbound network access)"
        echo "✓ All dependency installation tests completed successfully (skipped due to network)"
        return
    fi
    
    if ! check_opentofu_availability; then
        echo ""
        echo -e "${YELLOW}⊘${NC} Skipping dependency installation tests (OpenTofu download unavailable - GitHub may be experiencing issues)"
        echo "✓ All dependency installation tests completed successfully (skipped due to OpenTofu unavailability)"
        return
    fi
    
    test_dependency_installation
    test_full_installation_with_dependencies
    test_dependency_detection
    
    echo "✓ All dependency installation tests completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
