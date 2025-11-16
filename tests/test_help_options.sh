#!/usr/bin/env bash
# Validate that --help output for each command reflects the options handled in code.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

source "$TEST_DIR/test_helper.sh"

echo "Command help validation"
echo "======================="

validate_help_matches_code() {
    local command="$1"
    local function_name="cmd_${command}"
    local source_file="$SCRIPT_ROOT/lib/${function_name}.sh"

    echo ""
    echo "Test: exasol $command --help documents all options"

    local options=()
    if ! mapfile -t options < <(extract_command_options "$source_file" "$function_name"); then
        echo "Failed to extract options for $command" >&2
        exit 1
    fi

    local help_output
    if ! help_output=$("$SCRIPT_ROOT/exasol" "$command" --help 2>&1); then
        echo "Failed to run exasol $command --help" >&2
        exit 1
    fi

    if [[ ${#options[@]} -eq 0 ]]; then
        assert_contains "$help_output" "--help" "exasol $command --help is available"
        return
    fi

    for option in "${options[@]}"; do
        assert_contains "$help_output" "$option" "Help documents $option for $command"
    done
}

validate_help_matches_code "init"
validate_help_matches_code "deploy"
validate_help_matches_code "destroy"
validate_help_matches_code "status"
validate_help_matches_code "health"

test_summary
