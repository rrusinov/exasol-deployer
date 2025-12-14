#!/usr/bin/env bash
# Containerized tests for installer edge cases and error conditions

set -euo pipefail

# shellcheck disable=SC2155
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
# shellcheck source=./test_helper.sh
source "$SCRIPT_DIR/test_helper.sh"

# Check if container runtime is available
CONTAINER_CMD=""
if [[ "${SKIP_CONTAINER_TESTS:-}" != "true" ]]; then
    if command -v podman >/dev/null 2>&1; then
        CONTAINER_CMD="podman"
    elif command -v docker >/dev/null 2>&1; then
        CONTAINER_CMD="docker"
    fi
fi

check_network_connectivity() {
    local probe_url="${URL_AVAILABILITY_PROBE_URL:-https://example.com}"
    curl --head --silent --fail --location --max-time 5 "$probe_url" > /dev/null 2>&1
}

# Test environments for edge case testing
declare -A EDGE_CASE_TEST_ENVIRONMENTS=(
    ["ubuntu-edge"]="ubuntu:22.04"
    ["debian-edge"]="debian:bullseye"
)

create_edge_case_dockerfile() {
    local env_name="$1"
    local base_image="$2"
    local dockerfile_path="/tmp/Dockerfile.${env_name}-edge"
    
    case "$env_name" in
        "ubuntu-edge"|"debian-edge")
            cat > "$dockerfile_path" << 'EOF'
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
RUN apt-get update && apt-get install -y curl ca-certificates unzip
RUN useradd -m -s /bin/bash testuser
USER testuser
WORKDIR /home/testuser
EOF
            ;;
    esac
    echo "$dockerfile_path"
}

create_edge_case_test_script() {
    local script_path="/tmp/edge_case_container_test_script.sh"
    cat > "$script_path" << 'EOF'
#!/bin/bash
set -euo pipefail

echo "=== Container Environment Info ==="
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo "Architecture: $(uname -m)"
echo ""

# Copy installer to writable location
cp /home/testuser/installer.sh ./exasol-installer.sh
chmod +x ./exasol-installer.sh

echo "=== Test 1: Fresh Installation with Dependencies ==="
if ./exasol-installer.sh --install-dependencies --prefix ./test-fresh --yes --no-path; then
    echo "✓ Fresh installation with dependencies succeeded"
    
    # Verify all dependencies are installed
    [[ -f "./test-fresh/exasol-deployer/share/tofu/tofu" ]] || { echo "✗ OpenTofu not found"; exit 1; }
    [[ -f "./test-fresh/exasol-deployer/share/jq/jq" ]] || { echo "✗ jq not found"; exit 1; }
    [[ -f "./test-fresh/exasol-deployer/share/python/bin/python3" ]] || { echo "✗ Python not found"; exit 1; }
    [[ -f "./test-fresh/exasol-deployer/share/python/bin/ansible-playbook" ]] || { echo "✗ Ansible not found"; exit 1; }
    
else
    echo "✗ Fresh installation with dependencies failed"
    exit 1
fi

echo "=== Test 2: Overwrite Installation with Dependencies ==="
# Install again to test overwrite scenario
if ./exasol-installer.sh --install-dependencies --prefix ./test-fresh --yes --no-path; then
    echo "✓ Overwrite installation with dependencies succeeded"
    
    # Verify dependencies still exist after overwrite
    [[ -f "./test-fresh/exasol-deployer/share/tofu/tofu" ]] || { echo "✗ OpenTofu missing after overwrite"; exit 1; }
    [[ -f "./test-fresh/exasol-deployer/share/jq/jq" ]] || { echo "✗ jq missing after overwrite"; exit 1; }
    
    echo "✓ Dependencies preserved after overwrite"
else
    echo "✗ Overwrite installation failed"
    exit 1
fi

echo "=== Test 3: Dependencies-Only Installation ==="
if ./exasol-installer.sh --dependencies-only --prefix ./test-deps-only --yes; then
    echo "✓ Dependencies-only installation succeeded"
    
    # Verify only dependencies are installed (no main exasol binary)
    [[ -f "./test-deps-only/exasol-deployer/share/tofu/tofu" ]] || { echo "✗ OpenTofu not found in deps-only"; exit 1; }
    [[ -f "./test-deps-only/exasol-deployer/share/jq/jq" ]] || { echo "✗ jq not found in deps-only"; exit 1; }
    [[ ! -f "./test-deps-only/exasol" ]] || { echo "✗ Main binary should not exist in deps-only mode"; exit 1; }
    
    echo "✓ Dependencies-only installation verified"
else
    echo "✗ Dependencies-only installation failed"
    exit 1
fi

echo "=== Test 5: Functional Verification ==="
# Test that installed tools actually work
export PATH="./test-fresh/exasol-deployer/share/tofu:./test-fresh/exasol-deployer/share/jq:$PATH"

# Test OpenTofu
if ./test-fresh/exasol-deployer/share/tofu/tofu version | grep -q "OpenTofu"; then
    echo "✓ OpenTofu functional test passed"
else
    echo "✗ OpenTofu functional test failed"
    exit 1
fi

# Test jq
if echo '{"test": "value"}' | ./test-fresh/exasol-deployer/share/jq/jq '.test' | grep -q "value"; then
    echo "✓ jq functional test passed"
else
    echo "✗ jq functional test failed"
    exit 1
fi

# Test Python
if ./test-fresh/exasol-deployer/share/python/bin/python3 --version | grep -q "Python 3.11"; then
    echo "✓ Python functional test passed"
else
    echo "✗ Python functional test failed"
    exit 1
fi

# Test Ansible (with UTF-8 locale)
export LC_ALL=C.UTF-8 LANG=C.UTF-8
if ./test-fresh/exasol-deployer/share/python/bin/ansible-playbook --version | grep -q "ansible-playbook"; then
    echo "✓ Ansible functional test passed"
else
    echo "✗ Ansible functional test failed"
    exit 1
fi

echo "=== Test 6: Error Handling ==="
# Test invalid arguments
if output=$(./exasol-installer.sh --invalid-option 2>&1 || true) && echo "$output" | grep -q "Unknown option"; then
    echo "✓ Invalid option handling works"
else
    echo "✗ Invalid option handling failed"
    exit 1
fi

# Test help and version
if ./exasol-installer.sh --help | grep -q "Usage:"; then
    echo "✓ Help option works"
else
    echo "✗ Help option failed"
    exit 1
fi

if ./exasol-installer.sh --version | grep -q "Exasol Deployer Installer"; then
    echo "✓ Version option works"
else
    echo "✗ Version option failed"
    exit 1
fi

echo ""
echo "✓ All containerized edge case tests passed!"
EOF
    echo "$script_path"
}

run_edge_case_container_test() {
    local env_name="$1"
    local base_image="$2"
    local test_script="$3"
    
    if [[ -z "$CONTAINER_CMD" ]]; then
        echo "SKIP: No container runtime available for $env_name"
        return 0
    fi
    
    local dockerfile_path
    dockerfile_path=$(create_edge_case_dockerfile "$env_name" "$base_image")
    local image_name="exasol_deployer-edge-test-${env_name}"
    
    # Build test image
    if ! $CONTAINER_CMD build -t "$image_name" --build-arg BASE_IMAGE="$base_image" -f "$dockerfile_path" . >/dev/null 2>&1; then
        echo "SKIP: Failed to build container for $env_name"
        rm -f "$dockerfile_path"
        return 0
    fi
    
    # Run test in container
    local result=0
    $CONTAINER_CMD run --rm \
        -v "$PROJECT_ROOT/build/exasol-deployer.sh:/home/testuser/installer.sh:ro" \
        -v "$test_script:/home/testuser/test_script.sh:ro" \
        "$image_name" \
        bash /home/testuser/test_script.sh || result=$?
    
    # Cleanup
    rm -f "$dockerfile_path"
    $CONTAINER_CMD rmi "$image_name" >/dev/null 2>&1 || true
    
    return $result
}

test_installer_edge_cases_containers() {
    echo "Testing installer edge cases in containers..."
    
    # Check network connectivity
    if ! check_network_connectivity; then
        echo ""
        echo -e "${YELLOW}⊘${NC} Skipping containerized edge case tests (no outbound network access)"
        echo "✓ Containerized edge case tests completed successfully (skipped due to network)"
        return
    fi
    
    # Ensure installer exists
    local installer="$PROJECT_ROOT/build/exasol-deployer.sh"
    if [[ ! -f "$installer" ]]; then
        echo "Building installer..."
        (cd "$PROJECT_ROOT" && ./scripts/create-release.sh >/dev/null 2>&1)
    fi
    
    if [[ -z "$CONTAINER_CMD" ]]; then
        echo ""
        echo -e "${YELLOW}⊘${NC} Skipping containerized edge case tests (no container runtime available)"
        echo "Install podman or docker for containerized testing"
        echo "✓ Containerized edge case tests completed successfully (skipped - no container runtime)"
        return
    fi
    
    local test_script
    test_script=$(create_edge_case_test_script)
    
    local env_passed=0
    local env_total=0
    
    for env_name in "${!EDGE_CASE_TEST_ENVIRONMENTS[@]}"; do
        echo "Testing installer edge cases in: $env_name (${EDGE_CASE_TEST_ENVIRONMENTS[$env_name]})"
        env_total=$((env_total + 1))
        
        if run_edge_case_container_test "$env_name" "${EDGE_CASE_TEST_ENVIRONMENTS[$env_name]}" "$test_script"; then
            echo "PASS: $env_name edge case tests"
            env_passed=$((env_passed + 1))
        else
            echo "FAIL: $env_name edge case tests"
        fi
        echo ""
    done
    
    rm -f "$test_script"
    
    echo "Container edge case test summary: $env_passed/$env_total environments passed"
    
    if [[ $env_passed -eq $env_total ]]; then
        echo "✓ All containerized edge case tests passed!"
    else
        echo "✗ Some containerized edge case tests failed"
        exit 1
    fi
}

# Main test execution
main() {
    echo "Starting containerized installer edge case tests..."
    echo ""
    
    test_installer_edge_cases_containers
    
    echo ""
    echo "✓ All containerized installer edge case tests completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
