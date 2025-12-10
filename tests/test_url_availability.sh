#!/usr/bin/env bash
# Unit tests for URL availability in versions.conf
# Tests that all configured URLs are accessible without fully downloading them

set -uo pipefail  # Don't use -e, as we expect some tests to fail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/test_helper.sh"

# Path to versions.conf
VERSIONS_CONF="$PROJECT_ROOT/versions.conf"

echo "========================================="
echo "Testing URL Availability in versions.conf"
echo "========================================="
echo ""

check_network_connectivity() {
    local probe_url="${URL_AVAILABILITY_PROBE_URL:-https://example.com}"
    curl --head --silent --fail --location --max-time 5 "$probe_url" > /dev/null 2>&1
}

# Function to check if URL is accessible using HTTP HEAD request
# Returns 0 if accessible, 1 otherwise
check_url_accessible() {
    local url="$1"
    local description="${2:-$url}"

    # Skip file:// URLs as they reference local files
    if [[ "$url" == file://* ]]; then
        echo -e "${YELLOW}⊘${NC} Skipping local file URL: $description"
        return 0
    fi

    # Use curl with --head to only fetch headers (no download)
    # --silent: no progress bar
    # --fail: return error on HTTP errors
    # --location: follow redirects
    # --max-time 10: timeout after 10 seconds
    if curl --head --silent --fail --location --max-time 10 "$url" > /dev/null 2>&1; then
        assert_success 0 "URL accessible: $description"
        return 0
    else
        assert_failure 0 "URL NOT accessible: $description (URL: $url)"
        return 1
    fi
}

# Function to extract URLs from versions.conf
# Parses DB_DOWNLOAD_URL and C4_DOWNLOAD_URL fields
extract_urls_from_versions_conf() {
    local conf_file="$1"
    local current_version=""

    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Check if this is a version section header
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            current_version="${BASH_REMATCH[1]}"
            continue
        fi

        # Extract URL fields (skip lines with "placeholder" values)
        if [[ "$line" =~ ^(DB_DOWNLOAD_URL|C4_DOWNLOAD_URL)=(.+)$ ]]; then
            local field_name="${BASH_REMATCH[1]}"
            local url="${BASH_REMATCH[2]}"

            # Skip placeholder URLs or commented-out sections
            [[ -z "$current_version" ]] && continue
            [[ "$url" == *"placeholder"* ]] && continue

            # Output: version|field_name|url
            echo "${current_version}|${field_name}|${url}"
        fi
    done < "$conf_file"
}

# Main test execution
main() {
    # Check if versions.conf exists
    assert_file_exists "$VERSIONS_CONF" "versions.conf exists"

    if [[ ! -f "$VERSIONS_CONF" ]]; then
        echo -e "${RED}ERROR: versions.conf not found at $VERSIONS_CONF${NC}"
        exit 1
    fi

    if ! check_network_connectivity; then
        echo ""
        echo -e "${YELLOW}⊘${NC} Skipping URL availability tests (no outbound network access)"
        test_summary
        return
    fi

    echo ""
    echo "Extracting URLs from versions.conf..."
    echo ""

    # Extract and test each URL
    local url_count=0
    local tested_count=0

    while IFS='|' read -r version field_name url; do
        ((url_count++))

        # Skip file:// URLs from counting tested URLs
        if [[ "$url" != file://* ]]; then
            ((tested_count++))
        fi

        check_url_accessible "$url" "$version - $field_name"
    done < <(extract_urls_from_versions_conf "$VERSIONS_CONF")

    echo ""

    if [[ $url_count -eq 0 ]]; then
        echo -e "${YELLOW}WARNING: No URLs found in versions.conf (all may be placeholders or file:// URLs)${NC}"
    else
        echo "Found $url_count total URLs in versions.conf"
        echo "Tested $tested_count HTTP(S) URLs (skipped file:// URLs)"
    fi

    echo ""
    test_summary
}

# Run tests
main
