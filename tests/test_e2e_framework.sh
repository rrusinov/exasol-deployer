#!/usr/bin/env bash
# Test the E2E framework unit tests

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run Python unit tests for E2E framework
cd "$SCRIPT_DIR/e2e"
python3 -m unittest test_e2e_framework.py