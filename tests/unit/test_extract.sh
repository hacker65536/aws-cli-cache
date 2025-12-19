#!/usr/bin/env bash
#
# Unit tests for extract.sh module
#

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Test counters
declare -i PASSED=0
declare -i FAILED=0

# Load module under test
source "${PROJECT_ROOT}/lib/extract.sh"

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((FAILED++))
    fi
}

test_extract_ttl_from_filename() {
    echo "--- extract_ttl_from_filename ---"
    
    local result
    result=$(extract_ttl_from_filename "abc123_3600_12345.cache")
    assert_equals "3600" "$result" "extracts TTL from valid filename"
    
    result=$(extract_ttl_from_filename "hash_300_99999.cache")
    assert_equals "300" "$result" "extracts short TTL"
    
    if ! extract_ttl_from_filename "invalid.cache" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} returns error for invalid filename"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} should return error for invalid filename"
        ((FAILED++))
    fi
}

test_extract_profile() {
    echo "--- extract_profile ---"
    
    local result
    result=$(extract_profile "rds describe-db-clusters --profile my-profile")
    assert_equals "my-profile" "$result" "extracts profile from --profile"
    
    result=$(extract_profile "--profile test-profile rds describe-db-clusters")
    assert_equals "test-profile" "$result" "extracts profile at start"
    
    export AWS_PROFILE="env-profile"
    result=$(extract_profile "rds describe-db-clusters")
    assert_equals "env-profile" "$result" "uses AWS_PROFILE when not specified"
    unset AWS_PROFILE
    
    result=$(extract_profile "rds describe-db-clusters")
    assert_equals "default" "$result" "defaults to 'default'"
}

test_extract_service() {
    echo "--- extract_service ---"
    
    local result
    result=$(extract_service "rds" "describe-db-clusters")
    assert_equals "rds" "$result" "extracts service name"
    
    result=$(extract_service "--profile" "test" "ec2" "describe-instances")
    assert_equals "ec2" "$result" "skips --profile option"
    
    result=$(extract_service "--region" "us-east-1" "s3" "ls")
    assert_equals "s3" "$result" "skips --region option"
}

test_extract_region() {
    echo "--- extract_region ---"
    
    local result
    result=$(extract_region "rds describe-db-clusters --region us-west-2")
    assert_equals "us-west-2" "$result" "extracts region from --region"
    
    export AWS_REGION="ap-northeast-1"
    result=$(extract_region "rds describe-db-clusters")
    assert_equals "ap-northeast-1" "$result" "uses AWS_REGION when not specified"
    unset AWS_REGION
    
    result=$(extract_region "rds describe-db-clusters")
    assert_equals "global" "$result" "defaults to 'global'"
}

test_extract_action() {
    echo "--- extract_action ---"
    
    local result
    result=$(extract_action "rds" "rds" "describe-db-clusters")
    assert_equals "describe-db-clusters" "$result" "extracts action"
    
    result=$(extract_action "ec2" "--profile" "test" "ec2" "describe-instances")
    assert_equals "describe-instances" "$result" "extracts action with options"
}

test_extract_format() {
    echo "--- extract_format ---"
    
    local result
    result=$(extract_format "rds describe-db-clusters --output json")
    assert_equals "json" "$result" "extracts json format"
    
    result=$(extract_format "rds describe-db-clusters --output table")
    assert_equals "table" "$result" "extracts table format"
    
    result=$(extract_format "rds describe-db-clusters")
    assert_equals "json" "$result" "defaults to json"
}

# Run tests
echo "=== Extract Module Unit Tests ==="
echo ""

test_extract_ttl_from_filename
echo ""
test_extract_profile
echo ""
test_extract_service
echo ""
test_extract_region
echo ""
test_extract_action
echo ""
test_extract_format
echo ""

# Summary
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

[[ $FAILED -eq 0 ]]
