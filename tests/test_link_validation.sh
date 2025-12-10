#!/usr/bin/env bash
# Link validation test - validates that documentation links are functional
# **Feature: repo-public-release, Property 30: Link validation**
# **Validates: Requirements 7.2**

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/test_helper.sh"

echo "Link validation"
echo "==============="

# Function to extract links from markdown files
extract_links() {
    local file="$1"
    # Extract markdown links [text](url) - more precise pattern
    grep -oE '\]\([^)]+\)' "$file" 2>/dev/null | \
        sed 's/](\([^)]*\))/\1/' || true
}

# Function to check if a URL is accessible
check_url() {
    local url="$1"
    local timeout=10
    
    # Skip relative links and anchors
    if [[ "$url" =~ ^(#|\./) ]]; then
        return 0
    fi
    
    # Skip mailto links
    if [[ "$url" =~ ^mailto: ]]; then
        return 0
    fi
    
    # Check HTTP/HTTPS URLs
    if [[ "$url" =~ ^https?:// ]]; then
        if command -v curl >/dev/null 2>&1; then
            curl -s --max-time "$timeout" --head "$url" >/dev/null 2>&1
        elif command -v wget >/dev/null 2>&1; then
            wget -q --timeout="$timeout" --spider "$url" >/dev/null 2>&1
        else
            echo "Warning: Neither curl nor wget available for URL checking" >&2
            return 0  # Skip check if no tools available
        fi
    else
        return 0  # Skip non-HTTP URLs
    fi
}

# Function to check relative file links
check_relative_link() {
    local file="$1"
    local link="$2"
    local file_dir
    file_dir="$(dirname "$file")"
    
    # Skip anchors
    if [[ "$link" =~ ^# ]]; then
        return 0
    fi
    
    # Check if relative file exists
    if [[ "$link" =~ ^\. ]]; then
        local target_path="$file_dir/$link"
        if [[ -f "$target_path" || -d "$target_path" ]]; then
            return 0
        else
            return 1
        fi
    fi
    
    return 0
}

# Get all documentation files
doc_files=()
while IFS= read -r file; do
    [[ -n "$file" ]] && doc_files+=("$PROJECT_ROOT/$file")
done < <(cd "$PROJECT_ROOT" && git ls-files '*.md' '*.rst' '*.txt' 2>/dev/null | sort)

if [[ ${#doc_files[@]} -eq 0 ]]; then
    echo "No documentation files found"
    exit 0
fi

echo "Found ${#doc_files[@]} documentation files to check"

# Track results
total_links=0
broken_links=0
checked_urls=0

# Check each documentation file
for doc_file in "${doc_files[@]}"; do
    if [[ ! -f "$doc_file" ]]; then
        continue
    fi
    
    relative_path="${doc_file#"$PROJECT_ROOT/"}"
    echo "Checking links in: $relative_path"
    
    # Extract and check links
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        
        total_links=$((total_links + 1))
        
        # Check relative links
        if [[ "$link" =~ ^\. ]] || [[ "$link" =~ ^# ]]; then
            if ! check_relative_link "$doc_file" "$link"; then
                echo "  ✗ Broken relative link: $link"
                broken_links=$((broken_links + 1))
            fi
        # Check HTTP/HTTPS URLs
        elif [[ "$link" =~ ^https?:// ]]; then
            checked_urls=$((checked_urls + 1))
            if ! check_url "$link"; then
                echo "  ✗ Broken URL: $link"
                broken_links=$((broken_links + 1))
            fi
        fi
    done < <(extract_links "$doc_file")
done

echo ""
echo "Link validation summary:"
echo "  Total links found: $total_links"
echo "  URLs checked: $checked_urls"
echo "  Broken links: $broken_links"

# Test assertions
assert_equals "0" "$broken_links" "All documentation links should be functional"

# Summary
if [[ $broken_links -eq 0 ]]; then
    echo -e "${GREEN}✓${NC} All documentation links are functional"
else
    echo -e "${RED}✗${NC} Found $broken_links broken links"
fi

echo ""
echo "Tests: $TESTS_TOTAL, Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi