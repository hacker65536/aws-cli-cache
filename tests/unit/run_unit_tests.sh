#!/usr/bin/env bash
#
# Run all unit tests
#

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

declare -i TOTAL_PASSED=0
declare -i TOTAL_FAILED=0
declare -a FAILED_SUITES=()

run_test_suite() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)
    
    echo -e "${BLUE}=== Running: $test_name ===${NC}"
    echo ""
    
    if bash "$test_file"; then
        echo -e "${GREEN}✓ $test_name passed${NC}"
        ((TOTAL_PASSED++))
    else
        echo -e "${RED}✗ $test_name failed${NC}"
        FAILED_SUITES+=("$test_name")
        ((TOTAL_FAILED++))
    fi
    echo ""
}

echo "========================================"
echo "       AWS CLI Cache Unit Tests"
echo "========================================"
echo ""

# Run all test files
for test_file in "$SCRIPT_DIR"/test_*.sh; do
    if [[ -f "$test_file" ]]; then
        run_test_suite "$test_file"
    fi
done

# Summary
echo "========================================"
echo "            Final Summary"
echo "========================================"
echo -e "Test Suites Passed: ${GREEN}$TOTAL_PASSED${NC}"
echo -e "Test Suites Failed: ${RED}$TOTAL_FAILED${NC}"

if [[ $TOTAL_FAILED -gt 0 ]]; then
    echo ""
    echo -e "${RED}Failed Suites:${NC}"
    for suite in "${FAILED_SUITES[@]}"; do
        echo "  - $suite"
    done
    exit 1
fi

echo ""
echo -e "${GREEN}All unit tests passed!${NC}"
