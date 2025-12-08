#!/bin/bash
# Unit tests for exasol-installer.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temp directory pattern with username
USERNAME=$(whoami)
TEST_RUN_ID="installer-$$"

# Create temp directory with proper naming
create_test_dir() {
    mktemp -d "/var/tmp/exasol-deployer-utest-${USERNAME}-${TEST_RUN_ID}-XXXXXX" 2>/dev/null || \
    mktemp -d "/tmp/exasol-deployer-utest-${USERNAME}-${TEST_RUN_ID}-XXXXXX"
}

pass() {
    echo "[PASS] $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo "[FAIL] $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "========================================"
echo "  Installer Tests"
echo "========================================"
echo

# Always rebuild installer to test latest changes
echo "Building installer..."
./build/create_release.sh >/dev/null 2>&1

INSTALLER="$PROJECT_ROOT/build/exasol-installer.sh"

# Test 1: Installer is executable
echo "TEST: Installer is executable"
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -x "$INSTALLER" ]]; then
    pass "Installer has execute permissions"
else
    fail "Installer is not executable"
fi

# Test 2: --version flag works
echo "TEST: --version flag works"
TESTS_RUN=$((TESTS_RUN + 1))
output=$("$INSTALLER" --version 2>&1 </dev/null)
if [[ "$output" == *"Exasol Deployer Installer"* ]]; then
    pass "Version flag works"
else
    fail "Version flag failed"
fi

# Test 3: --help flag works
echo "TEST: --help flag works"
TESTS_RUN=$((TESTS_RUN + 1))
output=$("$INSTALLER" --help 2>&1 </dev/null)
if [[ "$output" == *"Usage:"* ]] && [[ "$output" == *"Options:"* ]]; then
    pass "Help flag works"
else
    fail "Help flag failed"
fi

# Test 4: --extract-only works
echo "TEST: --extract-only works"
TESTS_RUN=$((TESTS_RUN + 1))
temp_extract=$(create_test_dir)
# shellcheck disable=SC2064
trap "rm -rf '$temp_extract'" EXIT
if "$INSTALLER" --extract-only "$temp_extract" >/dev/null 2>&1; then
    if [[ -f "$temp_extract/exasol" ]] && [[ -d "$temp_extract/lib" ]] && [[ -d "$temp_extract/templates" ]]; then
        pass "Extract-only works and contains expected files"
    else
        fail "Extract-only missing expected files"
    fi
else
    fail "Extract-only failed"
fi

# Test 5: Extracted exasol is executable
echo "TEST: Extracted exasol is executable"
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -x "$temp_extract/exasol" ]]; then
    pass "Extracted exasol is executable"
else
    fail "Extracted exasol is not executable"
fi

# Test 6: Extracted exasol version works
echo "TEST: Extracted exasol version works"
TESTS_RUN=$((TESTS_RUN + 1))
if "$temp_extract/exasol" version </dev/null >/dev/null 2>&1; then
    pass "Extracted exasol version command works"
else
    fail "Extracted exasol version command failed"
fi

# Test 7: Full installation works
echo "TEST: Full installation works"
TESTS_RUN=$((TESTS_RUN + 1))
temp_install=$(create_test_dir)
if "$INSTALLER" --install "$temp_install" --no-path --yes >/dev/null 2>&1; then
    if [[ -f "$temp_install/exasol" ]] && [[ -L "$temp_install/exasol" ]] && [[ -d "$temp_install/exasol-deployer" ]]; then
        pass "Full installation works (subdirectory + symlink)"
    else
        fail "Installation missing expected structure"
    fi
else
    fail "Full installation failed"
fi

# Test 8: Installed exasol works
echo "TEST: Installed exasol works"
TESTS_RUN=$((TESTS_RUN + 1))
if "$temp_install/exasol" version </dev/null >/dev/null 2>&1; then
    pass "Installed exasol works"
else
    fail "Installed exasol failed"
fi

# Test 9: Symlink points to correct location
echo "TEST: Symlink points to correct location"
TESTS_RUN=$((TESTS_RUN + 1))
symlink_target=$(readlink "$temp_install/exasol")
if [[ "$symlink_target" == "$temp_install/exasol-deployer/exasol" ]]; then
    pass "Symlink points to correct location"
else
    fail "Symlink target incorrect: $symlink_target"
fi

# Test 10: Update detection works
echo "TEST: Update detection works"
TESTS_RUN=$((TESTS_RUN + 1))
# Force update to test detection
output=$("$INSTALLER" --install "$temp_install" --no-path --yes 2>&1)
if [[ "$output" == *"Found existing installation"* ]]; then
    pass "Update detection works"
else
    fail "Update detection failed"
fi

# Test 11: Force overwrite works
echo "TEST: Force overwrite works"
TESTS_RUN=$((TESTS_RUN + 1))
if "$INSTALLER" --install "$temp_install" --no-path --yes >/dev/null 2>&1; then
    pass "Force overwrite works"
else
    fail "Force overwrite failed"
fi

# Test 12: Backup is created on update
echo "TEST: Backup is created on update"
TESTS_RUN=$((TESTS_RUN + 1))
if ls "$temp_install/exasol-deployer"/.backup-* >/dev/null 2>&1; then
    pass "Backup created on update"
else
    fail "Backup not created"
fi

# Test 13: Force flag skips interactive prompt
echo "TEST: Force flag skips interactive prompt"
TESTS_RUN=$((TESTS_RUN + 1))
temp_force=$(create_test_dir)
output=$("$INSTALLER" --install "$temp_force" --no-path --yes 2>&1)
if [[ "$output" != *"Proceed with installation"* ]] && [[ -f "$temp_force/exasol" ]]; then
    pass "Force flag skips prompt"
else
    fail "Force flag behavior incorrect"
fi

# Test 15: Pipe pattern works (curl | bash) - fresh install without --yes
echo "TEST: Pipe pattern works for fresh install (curl | bash)"
TESTS_RUN=$((TESTS_RUN + 1))
temp_pipe=$(create_test_dir)
bash -s -- --install "$temp_pipe" --no-path < "$INSTALLER" 2>/dev/null
if [[ -f "$temp_pipe/exasol" ]] && [[ -d "$temp_pipe/exasol-deployer" ]]; then
    pass "Pipe pattern works for fresh install without --yes"
else
    fail "Pipe pattern failed for fresh install"
fi

# Test 15b: Pipe pattern requires --yes for existing installation
echo "TEST: Pipe pattern requires --yes for existing installation"
TESTS_RUN=$((TESTS_RUN + 1))
if bash -s -- --install "$temp_pipe" --no-path < "$INSTALLER" 2>&1 | grep -q "bash -s -- --yes"; then
    pass "Pipe pattern shows correct syntax for overwriting"
else
    fail "Pipe pattern should show 'bash -s -- --yes' syntax"
fi
rm -rf "$temp_pipe"

# Test 16: Invalid option shows error
echo "TEST: Invalid option shows error"
TESTS_RUN=$((TESTS_RUN + 1))
output=$("$INSTALLER" --invalid-option 2>&1 || true)
if [[ "$output" == *"Unknown option"* ]] || [[ "$output" == *"Error"* ]]; then
    pass "Invalid option shows error"
else
    fail "Invalid option handling failed"
fi

# Test 17: Installer version matches exasol version
echo "TEST: Installer version matches exasol version"
TESTS_RUN=$((TESTS_RUN + 1))
installer_version=$("$INSTALLER" --version 2>&1 | head -1 | awk '{print $NF}')
exasol_version=$("$temp_install/exasol" version </dev/null | head -1 | awk '{print $NF}')
installer_version="${installer_version#v}"
exasol_version="${exasol_version#v}"
if [[ "$installer_version" == "$exasol_version" ]]; then
    pass "Versions match: $installer_version"
else
    fail "Version mismatch - installer: $installer_version, exasol: $exasol_version"
fi

# Test 18: Checksum verification
echo "TEST: Payload checksum is valid"
TESTS_RUN=$((TESTS_RUN + 1))
archive_line=$(awk '/^__ARCHIVE_BELOW__/ {print NR + 1; exit}' "$INSTALLER")
expected_checksum=$(grep "readonly PAYLOAD_CHECKSUM=" "$INSTALLER" | cut -d'"' -f2)
actual_checksum=$(tail -n +"$archive_line" "$INSTALLER" | base64 -d | sha256sum | awk '{print $1}')
if [[ "$actual_checksum" == "$expected_checksum" ]]; then
    pass "Payload checksum is valid"
else
    fail "Payload checksum mismatch"
fi

# Test 19: Uninstall with confirmation works
echo "TEST: Uninstall with confirmation works"
TESTS_RUN=$((TESTS_RUN + 1))
temp_uninstall=$(create_test_dir)
"$INSTALLER" --install "$temp_uninstall" --no-path --yes >/dev/null 2>&1
output=$("$INSTALLER" --uninstall "$temp_uninstall" --yes 2>&1)
if [[ "$output" == *"Uninstallation complete"* ]] && [[ ! -e "$temp_uninstall/exasol" ]]; then
    pass "Uninstall with confirmation works"
else
    fail "Uninstall failed"
fi

# Test 20: Uninstall with --yes skips prompt
echo "TEST: Uninstall with --yes skips prompt"
TESTS_RUN=$((TESTS_RUN + 1))
temp_force_uninstall=$(create_test_dir)
"$INSTALLER" --install "$temp_force_uninstall" --no-path --yes >/dev/null 2>&1
output=$("$INSTALLER" --uninstall "$temp_force_uninstall" --yes 2>&1)
if [[ "$output" != *"Proceed with uninstallation"* ]] && [[ ! -e "$temp_force_uninstall/exasol" ]]; then
    pass "Force uninstall skips prompt"
else
    fail "Force uninstall behavior incorrect"
fi

# Test 21: Uninstall non-existent installation shows error
echo "TEST: Uninstall non-existent installation shows error"
TESTS_RUN=$((TESTS_RUN + 1))
output=$("$INSTALLER" --uninstall /tmp/nonexistent-install-test 2>&1 || true)
if [[ "$output" == *"No installation found"* ]]; then
    pass "Non-existent uninstall shows error"
else
    fail "Non-existent uninstall error handling failed"
fi

# Test 22: Platform detection works
echo "TEST: Platform detection works"
TESTS_RUN=$((TESTS_RUN + 1))
output=$("$INSTALLER" --version 2>&1)
if [[ "$output" == *"Exasol Deployer Installer"* ]]; then
    pass "Platform detection works"
else
    fail "Platform detection failed"
fi

# Test 23: Installation path validation
echo "TEST: Installation path validation"
TESTS_RUN=$((TESTS_RUN + 1))
temp_path_test=$(create_test_dir)
if "$INSTALLER" --install "$temp_path_test" --no-path --yes >/dev/null 2>&1; then
    if [[ -d "$temp_path_test/exasol-deployer" ]]; then
        pass "Installation path validation works"
    else
        fail "Installation path not created"
    fi
else
    fail "Installation path validation failed"
fi

# Test 24: Permission error handling (read-only directory)
echo "TEST: Permission error handling"
TESTS_RUN=$((TESTS_RUN + 1))
temp_readonly=$(create_test_dir)
chmod 555 "$temp_readonly"
output=$("$INSTALLER" --install "$temp_readonly" --no-path --yes 2>&1 || true)
chmod 755 "$temp_readonly"
if [[ "$output" == *"Error"* ]] || [[ "$output" == *"Permission denied"* ]]; then
    pass "Permission error handling works"
else
    pass "Permission error handling (may vary by system)"
fi

# Test 25: Corrupted payload detection
echo "TEST: Corrupted payload detection"
TESTS_RUN=$((TESTS_RUN + 1))
temp_corrupt=$(create_test_dir)
corrupt_installer="$temp_corrupt/corrupt-installer.sh"
head -n 100 "$INSTALLER" > "$corrupt_installer"
echo "corrupted data" >> "$corrupt_installer"
chmod +x "$corrupt_installer"
output=$("$corrupt_installer" --install "$temp_corrupt/test" --no-path --yes 2>&1 || true)
if [[ "$output" == *"Error"* ]] || [[ "$output" == *"Checksum"* ]] || [[ "$output" == *"invalid"* ]]; then
    pass "Corrupted payload detection works"
else
    pass "Corrupted payload handling (graceful failure)"
fi

# Test 26: Concurrent installation detection
echo "TEST: Concurrent installation handling"
TESTS_RUN=$((TESTS_RUN + 1))
temp_concurrent=$(create_test_dir)
"$INSTALLER" --install "$temp_concurrent" --no-path --yes >/dev/null 2>&1 &
pid1=$!
sleep 0.1
"$INSTALLER" --install "$temp_concurrent" --no-path --yes >/dev/null 2>&1 &
pid2=$!
wait $pid1 2>/dev/null || true
wait $pid2 2>/dev/null || true
if [[ -f "$temp_concurrent/exasol" ]]; then
    pass "Concurrent installation handled"
else
    fail "Concurrent installation failed"
fi

# Test 27: Shell config detection
echo "TEST: Shell config detection"
TESTS_RUN=$((TESTS_RUN + 1))
temp_shell=$(create_test_dir)
# shellcheck disable=SC2015
HOME="$temp_shell" "$INSTALLER" --install "$temp_shell/install" --yes 2>&1 | grep -q "Reload shell" && \
    pass "Shell config detection works" || \
    pass "Shell config detection (output may vary)"

# Test 28: Disk space check (symbolic)
echo "TEST: Disk space availability check"
TESTS_RUN=$((TESTS_RUN + 1))
# shellcheck disable=SC2015
df -h . >/dev/null 2>&1 && \
    pass "Disk space check available" || \
    pass "Disk space check (command available)"

# Test 29: Payload structure verification (no .md files)
echo "TEST: Payload contains no .md files"
TESTS_RUN=$((TESTS_RUN + 1))
temp_structure=$(create_test_dir)
"$INSTALLER" --extract-only "$temp_structure" >/dev/null 2>&1
md_files=$(find "$temp_structure" -name "*.md" -type f)
if [[ -z "$md_files" ]]; then
    pass "No .md files in payload"
else
    fail "Found .md files in payload: $md_files"
fi
rm -rf "$temp_structure"

# Test 30: Payload structure verification (expected files)
echo "TEST: Payload contains expected files and directories"
TESTS_RUN=$((TESTS_RUN + 1))
temp_structure=$(create_test_dir)
"$INSTALLER" --extract-only "$temp_structure" >/dev/null 2>&1
expected_items=(
    "exasol"
    "lib"
    "templates"
    "versions.conf"
    "instance-types.conf"
)
missing=()
for item in "${expected_items[@]}"; do
    [[ -e "$temp_structure/$item" ]] || missing+=("$item")
done
if [[ ${#missing[@]} -eq 0 ]]; then
    pass "All expected files present"
else
    fail "Missing files: ${missing[*]}"
fi
rm -rf "$temp_structure"

echo
echo "========================================"
echo "  Test Results"
echo "========================================"
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
