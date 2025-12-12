#!/bin/bash

# Test installation order and dependency handling
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Build installer if needed
if [[ ! -f "$PROJECT_ROOT/build/exasol-deployer.sh" ]]; then
    echo "Building installer..."
    "$PROJECT_ROOT/scripts/create-release.sh" >/dev/null 2>&1
fi

INSTALLER="$PROJECT_ROOT/build/exasol-deployer.sh"

test_installation_order_issue() {
    echo "=== Testing Installation Order Issue ==="
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Test the problematic case: --install-dependencies should install deps BEFORE main app
    echo "Test: Dependencies should be available during main app installation"
    
    # Create a container environment without system dependencies
    if command -v docker >/dev/null 2>&1; then
        echo "Testing in clean container environment..."
        
        local container_output
        container_output=$(docker run --rm -v "$PROJECT_ROOT/build:/installer" ubuntu:22.04 bash -c "
            apt-get update -qq >/dev/null 2>&1 && 
            apt-get install -y -qq curl unzip >/dev/null 2>&1 && 
            
            # Test --install-dependencies flag
            echo 'Testing --install-dependencies order...' &&
            timeout 120 /installer/exasol-deployer.sh --install-dependencies --prefix /tmp/test --yes --no-path 2>&1 | grep -E '(Installing dependencies|✓.*installed|Created symlink)' | head -10
        " 2>&1 || true)
        
        echo "Container output:"
        echo "$container_output"
        
        # Check if the output shows correct order
        if echo "$container_output" | grep -q "Installing dependencies" && echo "$container_output" | grep -q "Created symlink"; then
            # Check if dependencies come before symlink creation
            local deps_line symlink_line
            deps_line=$(echo "$container_output" | grep -n "Installing dependencies" | head -1 | cut -d: -f1)
            symlink_line=$(echo "$container_output" | grep -n "Created symlink" | head -1 | cut -d: -f1)
            
            if [[ -n "$deps_line" && -n "$symlink_line" && "$deps_line" -lt "$symlink_line" ]]; then
                echo "PASS: Dependencies installed before main application"
            else
                echo "FAIL: Dependencies not installed before main application"
                echo "Dependencies line: $deps_line, Symlink line: $symlink_line"
                rm -rf "$temp_dir"
                return 1
            fi
        else
            echo "FAIL: Could not verify installation order from output"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        echo "SKIP: Docker not available for container testing"
    fi
    
    rm -rf "$temp_dir"
    echo "Installation order test completed!"
}

test_double_dependency_installation() {
    echo "=== Testing for Double Dependency Installation ==="
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Test if dependencies are being installed twice
    echo "Test: Dependencies should not be installed twice"
    
    if command -v docker >/dev/null 2>&1; then
        local container_output
        container_output=$(docker run --rm -v "$PROJECT_ROOT/build:/installer" ubuntu:22.04 bash -c "
            apt-get update -qq >/dev/null 2>&1 && 
            apt-get install -y -qq curl unzip >/dev/null 2>&1 && 
            
            # Count how many times dependencies are installed
            timeout 120 /installer/exasol-deployer.sh --install-dependencies --prefix /tmp/test --yes --no-path 2>&1 | grep -c 'Installing dependencies' || echo '0'
        " 2>&1 || true)
        
        local install_count
        install_count=$(echo "$container_output" | tail -1)
        
        if [[ "$install_count" == "1" ]]; then
            echo "PASS: Dependencies installed exactly once"
        elif [[ "$install_count" == "2" ]]; then
            echo "FAIL: Dependencies installed twice (double installation bug)"
            rm -rf "$temp_dir"
            return 1
        else
            echo "WARN: Unexpected dependency installation count: $install_count"
        fi
    else
        echo "SKIP: Docker not available for container testing"
    fi
    
    rm -rf "$temp_dir"
    echo "Double installation test completed!"
}

main() {
    echo "Testing installation order and dependency handling..."
    echo
    
    test_installation_order_issue
    echo
    test_double_dependency_installation
    echo
    echo "All installation order tests completed!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
