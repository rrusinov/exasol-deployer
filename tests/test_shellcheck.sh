#!/usr/bin/env bash
# Lint all shell scripts with ShellCheck

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

SHELLCHECK_BIN="${SHELLCHECK:-shellcheck}"

echo "ShellCheck lint"
echo "================"

if ! command -v "$SHELLCHECK_BIN" >/dev/null 2>&1; then
    echo "ShellCheck is required but not found. Install shellcheck and retry." >&2
    exit 1
fi

if ! "$SHELLCHECK_BIN" --version >/dev/null 2>&1; then
    echo "ShellCheck is installed but failed to run. Set SHELLCHECK to a working binary to enable linting." >&2
    exit 0
fi

# Collect shell scripts (tracked and untracked) without relying on Bash 4 mapfile
shell_scripts=()
while IFS= read -r script; do
    [[ -n "$script" ]] && shell_scripts+=("$script")
done < <((git ls-files '*.sh' && git ls-files -o --exclude-standard '*.sh') | sort -u || true)

if [[ ${#shell_scripts[@]} -eq 0 ]]; then
    echo "No shell scripts found."
    exit 0
fi

tmp_output=$(mktemp)

for script in "${shell_scripts[@]}"; do
    if [[ ! -f "$script" ]]; then
        echo ""
        echo "Skipping (missing): $script"
        continue
    fi
    # Skip generated installer (contains base64 payload that shellcheck can't parse)
    if [[ "$script" == "build/exasol-installer.sh" ]]; then
        echo ""
        echo "Skipping (generated): $script"
        continue
    fi
    echo ""
    echo "Linting: $script"
    set +e
    "$SHELLCHECK_BIN" -x -e SC1091 -e SC2317 -e SC2155 -e SC2164 -e SC2034 "$script" >"$tmp_output" 2>&1
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        cat "$tmp_output"
    fi
    assert_success $rc "ShellCheck passed: $script"
done

rm -f "$tmp_output"

test_summary
