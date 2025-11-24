#!/usr/bin/env bash
# Validate that human-readable documentation stays in sync with the codebase.

# Resolve directories
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

source "$TEST_DIR/test_helper.sh"
source "$SCRIPT_ROOT/lib/cmd_init.sh"

README_FILE="$SCRIPT_ROOT/README.md"
CLOUD_OVERVIEW_DOC="$SCRIPT_ROOT/docs/CLOUD_SETUP.md"
README_CONTENT="$(cat "$README_FILE")"

echo "Documentation validation"
echo "========================"

# Extract the list of init flags documented in the README (between **Flags:** and **Configuration Flow**)
extract_readme_init_flags() {
    local readme_path="$1"
    
    # Get the directory where this script is located
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local python_helper="$script_dir/python-helpers/extract_readme_flags.py"
    
    if [[ ! -f "$python_helper" ]]; then
        echo "Error: Python helper not found: $python_helper" >&2
        return 1
    fi
    
    python3 "$python_helper" "$readme_path" "init"
}

test_cloud_provider_docs_linked() {
    echo ""
    echo "Test: Cloud provider documentation linked from README"

    if ! grep -q "CLOUD_SETUP" "$README_FILE"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping provider doc link check (README appears to be deployment-scoped)"
        return
    fi

    local overview_content=""
    if [[ -f "$CLOUD_OVERVIEW_DOC" ]]; then
        overview_content="$(cat "$CLOUD_OVERVIEW_DOC")"
    fi

    for provider in "${SUPPORTED_PROVIDERS[@]}"; do
        local upper_provider
        upper_provider=$(printf '%s' "$provider" | tr '[:lower:]' '[:upper:]')
        local doc_name="CLOUD_SETUP_${upper_provider}.md"
        local doc_rel_path="docs/$doc_name"
        local doc_abs_path="$SCRIPT_ROOT/$doc_rel_path"

        assert_file_exists "$doc_abs_path" "Doc exists for provider $provider"
        assert_contains "$README_CONTENT" "$doc_rel_path" "README links to $provider doc"

        if [[ -n "$overview_content" ]]; then
            assert_contains "$overview_content" "$doc_name" "Overview links to $provider doc"
        fi
    done
}

test_commands_documented_in_readme() {
    echo ""
    echo "Test: README documents every command listed in --help"

    if ! grep -q "### \`init\`" "$README_FILE"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping command documentation check (README does not contain CLI sections)"
        return
    fi

    local commands=()
    while IFS= read -r cmd; do
        [[ -n "$cmd" ]] && commands+=("$cmd")
    done < <("$SCRIPT_ROOT/exasol" --help 2>/dev/null | awk '
        /Available Commands:/ {capture=1; next}
        capture {
            if ($0 ~ /^[[:space:]]*$/) { exit }
            sub(/^[[:space:]]+/, "", $0)
            print $1
        }')

    if [[ ${#commands[@]} -eq 0 ]]; then
        echo "Failed to parse exasol --help output" >&2
        exit 1
    fi

    for cmd in "${commands[@]}"; do
        assert_contains "$README_CONTENT" "### \`$cmd\`" "README contains section for '$cmd'"
    done
}

test_init_flags_documented() {
    echo ""
    echo "Test: README init flags match cmd_init options"

    if ! grep -q "### \`init\`" "$README_FILE"; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -e "${YELLOW}⊘${NC} Skipping init flag comparison (README does not contain CLI sections)"
        return
    fi

    local readme_flags=()
    while IFS= read -r flag; do
        [[ -n "$flag" ]] && readme_flags+=("$flag")
    done < <(extract_readme_init_flags "$README_FILE")

    if [[ ${#readme_flags[@]} -eq 0 ]]; then
        echo "Failed to extract init flags from README" >&2
        exit 1
    fi

    local code_flags=()
    while IFS= read -r flag; do
        [[ -n "$flag" ]] && code_flags+=("$flag")
    done < <(extract_command_options "$SCRIPT_ROOT/lib/cmd_init.sh" "cmd_init")

    if [[ ${#code_flags[@]} -eq 0 ]]; then
        echo "Failed to extract init flags from cmd_init" >&2
        exit 1
    fi

    local readme_flag_string=" ${readme_flags[*]} "
    local code_flag_string=" ${code_flags[*]} "

    for flag in "${code_flags[@]}"; do
        assert_contains "$readme_flag_string" " $flag " "README documents flag: $flag"
    done

    for flag in "${readme_flags[@]}"; do
        assert_contains "$code_flag_string" " $flag " "Flag $flag exists in cmd_init"
    done
}

# Execute tests
test_cloud_provider_docs_linked
test_commands_documented_in_readme
test_init_flags_documented

test_summary
