#!/usr/bin/env bash
# Style consistency test - validates consistent formatting across the project
# **Feature: repo-public-release, Property 31: Style consistency checking**
# **Validates: Requirements 7.3**

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/test_helper.sh"

echo "Style consistency validation"
echo "============================"

# Function to check shell script style consistency
check_shell_style() {
    local file="$1"
    local issues=0
    
    # Check shebang
    local first_line
    first_line="$(head -n1 "$file")"
    if [[ "$first_line" != "#!/usr/bin/env bash" ]]; then
        echo "  ✗ Incorrect shebang in $file: $first_line"
        issues=$((issues + 1))
    fi
    
    # Check for consistent indentation (should be 4 spaces, not tabs)
    if grep -q $'\t' "$file"; then
        echo "  ✗ Found tabs instead of spaces in $file"
        issues=$((issues + 1))
    fi
    
    # Check for trailing whitespace
    if grep -q '[[:space:]]$' "$file"; then
        echo "  ✗ Found trailing whitespace in $file"
        issues=$((issues + 1))
    fi
    
    # Check for consistent function definition style
    if grep -q '^[[:space:]]*function[[:space:]]\+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(' "$file"; then
        echo "  ✗ Found 'function' keyword with parentheses in $file (use 'function_name() {' style)"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Function to check markdown style consistency
check_markdown_style() {
    local file="$1"
    local issues=0
    
    # Check for trailing whitespace
    if grep -q '[[:space:]]$' "$file"; then
        echo "  ✗ Found trailing whitespace in $file"
        issues=$((issues + 1))
    fi
    
    # Check for consistent heading style (should use # not underlines)
    if grep -q '^[=]\+$\|^[-]\+$' "$file"; then
        echo "  ✗ Found underline-style headings in $file (use # style)"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Function to check YAML style consistency
check_yaml_style() {
    local file="$1"
    local issues=0
    
    # Check for tabs (YAML should use spaces)
    if grep -q $'\t' "$file"; then
        echo "  ✗ Found tabs in YAML file $file (use spaces)"
        issues=$((issues + 1))
    fi
    
    # Check for trailing whitespace
    if grep -q '[[:space:]]$' "$file"; then
        echo "  ✗ Found trailing whitespace in $file"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Function to check JSON style consistency
check_json_style() {
    local file="$1"
    local issues=0
    
    # Check if JSON is valid
    if command -v jq >/dev/null 2>&1; then
        if ! jq empty "$file" >/dev/null 2>&1; then
            echo "  ✗ Invalid JSON in $file"
            issues=$((issues + 1))
        fi
    fi
    
    # Check for trailing whitespace
    if grep -q '[[:space:]]$' "$file"; then
        echo "  ✗ Found trailing whitespace in $file"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Get all code files
shell_files=()
markdown_files=()
yaml_files=()
json_files=()

while IFS= read -r file; do
    [[ -n "$file" ]] && shell_files+=("$PROJECT_ROOT/$file")
done < <(cd "$PROJECT_ROOT" && git ls-files '*.sh' 2>/dev/null | sort)

while IFS= read -r file; do
    [[ -n "$file" ]] && markdown_files+=("$PROJECT_ROOT/$file")
done < <(cd "$PROJECT_ROOT" && git ls-files '*.md' 2>/dev/null | sort)

while IFS= read -r file; do
    [[ -n "$file" ]] && yaml_files+=("$PROJECT_ROOT/$file")
done < <(cd "$PROJECT_ROOT" && git ls-files '*.yml' '*.yaml' 2>/dev/null | sort)

while IFS= read -r file; do
    [[ -n "$file" ]] && json_files+=("$PROJECT_ROOT/$file")
done < <(cd "$PROJECT_ROOT" && git ls-files '*.json' 2>/dev/null | sort)

echo "Found files to check:"
echo "  Shell scripts: ${#shell_files[@]}"
echo "  Markdown files: ${#markdown_files[@]}"
echo "  YAML files: ${#yaml_files[@]}"
echo "  JSON files: ${#json_files[@]}"
echo ""

# Track results
total_issues=0

# Check shell scripts
if [[ ${#shell_files[@]} -gt 0 ]]; then
    echo "Checking shell script style consistency..."
    for file in "${shell_files[@]}"; do
        if [[ -f "$file" ]]; then
            relative_path="${file#"$PROJECT_ROOT/"}"
            if ! check_shell_style "$file"; then
                total_issues=$((total_issues + $?))
            fi
        fi
    done
fi

# Check markdown files
if [[ ${#markdown_files[@]} -gt 0 ]]; then
    echo "Checking markdown style consistency..."
    for file in "${markdown_files[@]}"; do
        if [[ -f "$file" ]]; then
            relative_path="${file#"$PROJECT_ROOT/"}"
            if ! check_markdown_style "$file"; then
                total_issues=$((total_issues + $?))
            fi
        fi
    done
fi

# Check YAML files
if [[ ${#yaml_files[@]} -gt 0 ]]; then
    echo "Checking YAML style consistency..."
    for file in "${yaml_files[@]}"; do
        if [[ -f "$file" ]]; then
            relative_path="${file#"$PROJECT_ROOT/"}"
            if ! check_yaml_style "$file"; then
                total_issues=$((total_issues + $?))
            fi
        fi
    done
fi

# Check JSON files
if [[ ${#json_files[@]} -gt 0 ]]; then
    echo "Checking JSON style consistency..."
    for file in "${json_files[@]}"; do
        if [[ -f "$file" ]]; then
            relative_path="${file#"$PROJECT_ROOT/"}"
            if ! check_json_style "$file"; then
                total_issues=$((total_issues + $?))
            fi
        fi
    done
fi

echo ""
echo "Style consistency summary:"
echo "  Total style issues found: $total_issues"

# Test assertions
assert_equals "0" "$total_issues" "Code should follow consistent style guidelines"

# Summary
if [[ $total_issues -eq 0 ]]; then
    echo -e "${GREEN}✓${NC} All files follow consistent style guidelines"
else
    echo -e "${RED}✗${NC} Found $total_issues style consistency issues"
fi

echo ""
echo "Tests: $TESTS_TOTAL, Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi