#!/usr/bin/env bash
# Verify Terraform/OpenTofu templates are already formatted

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

die() {
    echo -e "${RED}$*${NC}"
    exit 1
}

main() {
    if ! command -v tofu >/dev/null 2>&1; then
        echo -e "${YELLOW}⊘${NC} Skipping formatting check (tofu not available)"
        return 0
    fi

    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    local -a dirs=(
        "templates/terraform-aws"
        "templates/terraform-azure"
        "templates/terraform-common"
        "templates/terraform-digitalocean"
        "templates/terraform-gcp"
        "templates/terraform-hetzner"
        "templates/terraform-libvirt"
    )

    local all_ok=true

    for d in "${dirs[@]}"; do
        echo ""
        echo "Checking formatting in ${d}"
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        if (cd "${root}/${d}" && tofu fmt -check >/dev/null); then
            echo -e "${GREEN}✓${NC} ${d} formatted"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}✗${NC} ${d} formatting issues"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            all_ok=false
        fi
    done

    echo ""
    echo "Formatting check summary: total=${TESTS_TOTAL}, passed=${TESTS_PASSED}, failed=${TESTS_FAILED}"

    $all_ok
}

main "$@"
