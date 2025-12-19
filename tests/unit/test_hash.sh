#!/usr/bin/env bash
#
# Unit tests for hash.sh module
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
source "${PROJECT_ROOT}/lib/hash.sh"

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

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [[ "$not_expected" != "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name (values should differ)"
        ((FAILED++))
    fi
}

test_generate_params_hash() {
    echo "--- generate_params_hash ---"
    
    local hash1 hash2 hash3
    
    # Same params should produce same hash
    hash1=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier cluster1")
    hash2=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier cluster1")
    assert_equals "$hash1" "$hash2" "same params produce same hash"
    
    # Different params should produce different hash
    hash3=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier cluster2")
    assert_not_equals "$hash1" "$hash3" "different params produce different hash"
    
    # Hash should be 16 characters
    if [[ ${#hash1} -eq 16 ]]; then
        echo -e "${GREEN}✓${NC} hash is 16 characters"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} hash should be 16 characters (got ${#hash1})"
        ((FAILED++))
    fi
    
    # --region, --profile, --output should be excluded
    local hash_with_region hash_without_region
    hash_with_region=$(generate_params_hash "rds describe-db-clusters --region us-east-1 --db-cluster-identifier cluster1")
    hash_without_region=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier cluster1")
    assert_equals "$hash_with_region" "$hash_without_region" "--region is excluded from hash"
    
    local hash_with_profile hash_without_profile
    hash_with_profile=$(generate_params_hash "rds describe-db-clusters --profile test --db-cluster-identifier cluster1")
    hash_without_profile=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier cluster1")
    assert_equals "$hash_with_profile" "$hash_without_profile" "--profile is excluded from hash"
}

test_generate_cache_key() {
    echo "--- generate_cache_key ---"
    
    local key1 key2 key3
    
    # Same command should produce same key
    key1=$(generate_cache_key "rds describe-db-clusters --profile test")
    key2=$(generate_cache_key "rds describe-db-clusters --profile test")
    assert_equals "$key1" "$key2" "same command produces same key"
    
    # Different command should produce different key
    key3=$(generate_cache_key "rds describe-db-clusters --profile other")
    assert_not_equals "$key1" "$key3" "different command produces different key"
    
    # Key should be 64 characters (full SHA256)
    if [[ ${#key1} -eq 64 ]]; then
        echo -e "${GREEN}✓${NC} key is 64 characters"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} key should be 64 characters (got ${#key1})"
        ((FAILED++))
    fi
    
    # Key should only contain hex characters
    if [[ "$key1" =~ ^[a-f0-9]+$ ]]; then
        echo -e "${GREEN}✓${NC} key contains only hex characters"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} key should contain only hex characters"
        ((FAILED++))
    fi
}

# Run tests
echo "=== Hash Module Unit Tests ==="
echo ""

test_generate_params_hash
echo ""
test_generate_cache_key
echo ""

# Summary
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

[[ $FAILED -eq 0 ]]
