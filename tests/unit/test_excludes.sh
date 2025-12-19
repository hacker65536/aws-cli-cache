#!/usr/bin/env bash
#
# Unit tests for excludes.sh module
#

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly TEST_CONFIG_DIR="/tmp/aws_cache_test_excludes_$$"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Test counters
declare -i PASSED=0
declare -i FAILED=0

# Setup test environment BEFORE sourcing module
mkdir -p "$TEST_CONFIG_DIR"
export CACHE_EXCLUDE_CONFIG="$TEST_CONFIG_DIR/cache-exclude"

# Source module at top level (not in function) so declare -a works globally
source "${PROJECT_ROOT}/lib/excludes.sh"

cleanup() {
    rm -rf "$TEST_CONFIG_DIR"
}

trap cleanup EXIT

reset_test_state() {
    # Reset module state for fresh test
    IS_EXCLUDES_LOADED=false
    CACHED_EXCLUDE_RULES=()
    rm -f "$CACHE_EXCLUDE_CONFIG"
}

assert_cacheable() {
    local service="$1"
    local action="$2"
    local test_name="$3"
    
    if is_cacheable "$service" "$action"; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name (expected cacheable)"
        ((FAILED++))
    fi
}

assert_not_cacheable() {
    local service="$1"
    local action="$2"
    local test_name="$3"
    
    if ! is_cacheable "$service" "$action"; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name (expected not cacheable)"
        ((FAILED++))
    fi
}

test_default_excludes() {
    echo "--- Default Exclude Rules ---"
    reset_test_state
    
    # Read operations should be cacheable
    assert_cacheable "rds" "describe-db-clusters" "rds:describe-db-clusters is cacheable"
    assert_cacheable "ec2" "describe-instances" "ec2:describe-instances is cacheable"
    assert_cacheable "sts" "get-caller-identity" "sts:get-caller-identity is cacheable"
    
    # Write operations should not be cacheable
    assert_not_cacheable "rds" "create-db-cluster" "rds:create-db-cluster is not cacheable"
    assert_not_cacheable "ec2" "run-instances" "ec2:run-instances is not cacheable"
    assert_not_cacheable "lambda" "invoke" "lambda:invoke is not cacheable"
    assert_not_cacheable "s3" "put-object" "s3:put-object is not cacheable"
}

test_custom_excludes() {
    echo "--- Custom Exclude Rules ---"
    reset_test_state
    
    # Create custom exclude file
    cat > "$CACHE_EXCLUDE_CONFIG" << 'EOF'
# Custom rules
cloudwatch:describe-alarms
s3:*
*:list-buckets
EOF
    
    # Test custom exact match
    assert_not_cacheable "cloudwatch" "describe-alarms" "custom exact match works"
    
    # Test service wildcard
    assert_not_cacheable "s3" "list-objects" "service wildcard works"
    assert_not_cacheable "s3" "get-object" "service wildcard works for all actions"
    
    # Test action wildcard
    assert_not_cacheable "ec2" "list-buckets" "action wildcard works"
    assert_not_cacheable "iam" "list-buckets" "action wildcard works for all services"
    
    # Non-excluded should still be cacheable
    assert_cacheable "cloudwatch" "get-metric-statistics" "non-excluded action is cacheable"
}

test_reset_cache() {
    echo "--- Reset Cache ---"
    reset_test_state
    
    # Load rules
    load_cache_excludes > /dev/null
    
    if [[ "$IS_EXCLUDES_LOADED" == true ]]; then
        echo -e "${GREEN}✓${NC} rules are loaded"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} rules should be loaded"
        ((FAILED++))
    fi
    
    # Reset
    reset_excludes_cache
    
    if [[ "$IS_EXCLUDES_LOADED" == false ]]; then
        echo -e "${GREEN}✓${NC} cache is reset"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} cache should be reset"
        ((FAILED++))
    fi
}

# Run tests
echo "=== Excludes Module Unit Tests ==="
echo ""

test_default_excludes
echo ""
test_custom_excludes
echo ""
test_reset_cache
echo ""

# Summary
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

[[ $FAILED -eq 0 ]]
