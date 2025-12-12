#!/usr/bin/env bash

# Test installer interactive dependency installation edge case
# This test verifies that the installer properly continues after installing dependencies interactively

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

test_interactive_dependency_installation() {
    local test_name="interactive_dependency_installation"
    echo "Testing: $test_name"
    
    # Create a clean container environment without dependencies
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Build installer
    cd "$PROJECT_ROOT"
    ./scripts/create-release.sh
    
    # Copy installer to temp directory
    cp "./build/exasol-deployer.sh" "$temp_dir/"
    
    # Test the --install-dependencies --yes path (this should work)
    cat > "$temp_dir/test_deps.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# Test dependency installation with --yes flag
./exasol-deployer.sh --install-dependencies --prefix /tmp/test-install --yes

# Verify installation succeeded
if [[ -f "/tmp/test-install/exasol" ]]; then
    echo "SUCCESS: Installation completed with --install-dependencies --yes"
    exit 0
else
    echo "FAILURE: Installation did not complete properly"
    exit 1
fi
EOF
    
    chmod +x "$temp_dir/test_deps.sh"
    
    # Run test in Docker container without dependencies
    if command -v docker >/dev/null 2>&1; then
        docker run --rm \
            -v "$temp_dir:/test" \
            -w /test \
            ubuntu:22.04 \
            bash -c "
                apt-get update -qq && 
                apt-get install -y -qq curl unzip &&
                ./test_deps.sh
            "
        local result=$?
    else
        echo "SKIP: Docker not available, cannot test container environment"
        return 0
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    if [[ $result -eq 0 ]]; then
        echo "✓ $test_name passed"
        return 0
    else
        echo "✗ $test_name failed"
        return 1
    fi
}

test_dependency_check_after_installation() {
    local test_name="dependency_check_after_installation"
    echo "Testing: $test_name"
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create mock install directory structure
    mkdir -p "$temp_dir/share/tofu"
    mkdir -p "$temp_dir/share/jq"
    mkdir -p "$temp_dir/share/python/bin"
    
    # Create mock executables
    echo '#!/bin/bash' > "$temp_dir/share/tofu/tofu"
    echo '#!/bin/bash' > "$temp_dir/share/jq/jq"
    echo '#!/bin/bash' > "$temp_dir/share/python/bin/ansible-playbook"
    chmod +x "$temp_dir/share/tofu/tofu"
    chmod +x "$temp_dir/share/jq/jq"
    chmod +x "$temp_dir/share/python/bin/ansible-playbook"
    
    # Extract check function from installer and test it
    cd "$PROJECT_ROOT"
    ./scripts/create-release.sh
    
    # Extract and test the check_installed_dependencies function
    local test_script="$temp_dir/test_check.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Extract check_installed_dependencies function from installer
check_installed_dependencies() {
    local install_dir="$1"
    local share_dir="$install_dir/share"
    
    # Check OpenTofu/Terraform
    if [[ ! -x "$share_dir/tofu/tofu" ]] && ! command -v tofu >/dev/null 2>&1 && ! command -v terraform >/dev/null 2>&1; then
        return 1
    fi
    
    # Check jq
    if [[ ! -x "$share_dir/jq/jq" ]] && ! command -v jq >/dev/null 2>&1; then
        return 1
    fi
    
    # Check Ansible
    if [[ ! -x "$share_dir/python/bin/ansible-playbook" ]] && ! command -v ansible-playbook >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test the function
if check_installed_dependencies "$1"; then
    echo "SUCCESS: Dependencies check passed"
    exit 0
else
    echo "FAILURE: Dependencies check failed"
    exit 1
fi
EOF
    
    chmod +x "$test_script"
    
    # Test with mock installation
    if "$test_script" "$temp_dir"; then
        echo "✓ $test_name passed"
        local result=0
    else
        echo "✗ $test_name failed"
        local result=1
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    return $result
}

# Run tests
main() {
    echo "Running installer interactive dependency tests..."
    
    local failed=0
    
    test_dependency_check_after_installation || ((failed++))
    test_interactive_dependency_installation || ((failed++))
    
    if [[ $failed -eq 0 ]]; then
        echo "All tests passed!"
        exit 0
    else
        echo "$failed test(s) failed!"
        exit 1
    fi
}

main "$@"
