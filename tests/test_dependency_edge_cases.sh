#!/bin/bash

# Test dependency detection edge cases
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$PROJECT_ROOT/build/exasol-deployer.sh"

test_partial_portable_installation() {
    echo "=== Testing Partial Portable Installation Edge Cases ==="
    
    if ! command -v docker >/dev/null 2>&1; then
        echo "SKIP: Docker not available"
        return 0
    fi
    
    local temp_dir
    temp_dir=$(mktemp -d)
    cp "$INSTALLER" "$temp_dir/installer.sh"
    
    # Test scenario: Install dependencies, then remove one portable tool
    docker run --rm -v "$temp_dir:/test" -w /test ubuntu:22.04 bash -c "
        apt-get update -qq >/dev/null 2>&1 && 
        apt-get install -y -qq curl unzip >/dev/null 2>&1 && 
        
        echo 'Test 1: Install all dependencies first' &&
        ./installer.sh --dependencies-only --yes >/dev/null 2>&1 &&
        
        echo 'Test 2: Remove portable jq to simulate partial installation' &&
        rm -f /root/.local/bin/exasol-deployer/share/jq/jq &&
        
        echo 'Test 3: Check if missing jq is detected correctly' &&
        output=\$(./installer.sh --yes 2>&1 || true) &&
        
        if echo \"\$output\" | grep -q 'Missing tools.*jq'; then
            echo 'PASS: Missing portable jq detected correctly'
        else
            echo 'FAIL: Missing portable jq not detected'
            echo \"Output: \$output\"
            exit 1
        fi &&
        
        echo 'Test 4: Remove portable OpenTofu' &&
        rm -f /root/.local/bin/exasol-deployer/share/tofu/tofu &&
        
        echo 'Test 5: Check if missing OpenTofu is detected' &&
        output=\$(./installer.sh --yes 2>&1 || true) &&
        
        if echo \"\$output\" | grep -q 'Missing tools.*OpenTofu'; then
            echo 'PASS: Missing portable OpenTofu detected correctly'
        else
            echo 'FAIL: Missing portable OpenTofu not detected'
            echo \"Output: \$output\"
            exit 1
        fi
    " || { rm -rf "$temp_dir"; return 1; }
    
    rm -rf "$temp_dir"
    echo "All partial installation tests passed!"
}

test_mixed_system_portable() {
    echo "=== Testing Mixed System/Portable Dependencies ==="
    
    if ! command -v docker >/dev/null 2>&1; then
        echo "SKIP: Docker not available"
        return 0
    fi
    
    local temp_dir
    temp_dir=$(mktemp -d)
    cp "$INSTALLER" "$temp_dir/installer.sh"
    
    # Test scenario: Some tools available in system, some portable
    docker run --rm -v "$temp_dir:/test" -w /test ubuntu:22.04 bash -c "
        apt-get update -qq >/dev/null 2>&1 && 
        apt-get install -y -qq curl unzip jq >/dev/null 2>&1 && 
        
        echo 'Test 1: Install only some dependencies (not jq since system has it)' &&
        ./installer.sh --dependencies-only --yes >/dev/null 2>&1 &&
        
        echo 'Test 2: Remove portable jq (should use system jq)' &&
        rm -f /root/.local/bin/exasol-deployer/share/jq/jq &&
        
        echo 'Test 3: Check that system jq is used, no missing tools' &&
        output=\$(./installer.sh --yes 2>&1 || true) &&
        
        if echo \"\$output\" | grep -q 'Required dependencies are available'; then
            echo 'PASS: Mixed system/portable dependencies work correctly'
        else
            echo 'FAIL: Mixed dependencies not handled correctly'
            echo \"Output: \$output\"
            exit 1
        fi
    " || { rm -rf "$temp_dir"; return 1; }
    
    rm -rf "$temp_dir"
    echo "Mixed system/portable test passed!"
}

main() {
    echo "Testing dependency detection edge cases..."
    echo
    
    test_partial_portable_installation
    echo
    test_mixed_system_portable
    echo
    echo "All dependency edge case tests completed!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
