#!/usr/bin/env bash
#
# Unit tests for profile_region.sh
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/lib/profile_region.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

#######################################
# Assert equality
#######################################
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++)) || true
    
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
        return 0
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        return 0  # Don't fail the script
    fi
}

#######################################
# Setup test AWS config file
#######################################
setup_test_config() {
    local test_config_dir
    test_config_dir=$(mktemp -d)
    local test_config_file="$test_config_dir/config"
    
    cat > "$test_config_file" << 'EOF'
[default]
region = us-east-1
output = json

[profile dev]
region = us-west-2
output = json

[profile prod]
region = ap-northeast-1
output = json

[profile no-region]
output = json

[sso-session my-sso]
sso_start_url = https://example.awsapps.com/start
sso_region = us-east-1

[profile sso-profile]
sso_session = my-sso
region = eu-west-1
EOF
    
    echo "$test_config_file"
}

#######################################
# Cleanup test config
#######################################
cleanup_test_config() {
    local test_config_file="$1"
    local test_config_dir
    test_config_dir=$(dirname "$test_config_file")
    rm -rf "$test_config_dir"
}

#######################################
# Test: Parse AWS config file
#######################################
test_load_profile_region_cache() {
    echo "=== Test: load_profile_region_cache ==="
    
    local test_config
    test_config=$(setup_test_config)
    
    # Save original and set test config
    local original_config="${AWS_CONFIG_FILE:-}"
    export AWS_CONFIG_FILE="$test_config"
    
    # Clear cache before test
    clear_profile_region_cache
    
    # Load cache
    load_profile_region_cache
    
    # Verify cache loaded
    assert_equals "true" "$_PROFILE_REGION_CACHE_LOADED" "Cache should be marked as loaded"
    
    # Restore original
    if [[ -n "$original_config" ]]; then
        export AWS_CONFIG_FILE="$original_config"
    else
        unset AWS_CONFIG_FILE
    fi
    
    cleanup_test_config "$test_config"
    clear_profile_region_cache
}

#######################################
# Test: Get region for profiles
#######################################
test_get_profile_region() {
    echo "=== Test: get_profile_region ==="
    
    local test_config
    test_config=$(setup_test_config)
    
    local original_config="${AWS_CONFIG_FILE:-}"
    export AWS_CONFIG_FILE="$test_config"
    clear_profile_region_cache
    
    # Test default profile
    local region
    region=$(get_profile_region "default")
    assert_equals "us-east-1" "$region" "default profile should have us-east-1"
    
    # Test dev profile
    region=$(get_profile_region "dev")
    assert_equals "us-west-2" "$region" "dev profile should have us-west-2"
    
    # Test prod profile
    region=$(get_profile_region "prod")
    assert_equals "ap-northeast-1" "$region" "prod profile should have ap-northeast-1"
    
    # Test sso-profile
    region=$(get_profile_region "sso-profile")
    assert_equals "eu-west-1" "$region" "sso-profile should have eu-west-1"
    
    # Test profile without region
    if get_profile_region "no-region" > /dev/null 2>&1; then
        ((TESTS_RUN++))
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} no-region profile should return failure"
    else
        ((TESTS_RUN++))
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} no-region profile correctly returns failure"
    fi
    
    # Test non-existent profile
    if get_profile_region "nonexistent" > /dev/null 2>&1; then
        ((TESTS_RUN++))
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} nonexistent profile should return failure"
    else
        ((TESTS_RUN++))
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} nonexistent profile correctly returns failure"
    fi
    
    # Restore
    if [[ -n "$original_config" ]]; then
        export AWS_CONFIG_FILE="$original_config"
    else
        unset AWS_CONFIG_FILE
    fi
    
    cleanup_test_config "$test_config"
    clear_profile_region_cache
}

#######################################
# Test: resolve_region with various inputs
#######################################
test_resolve_region() {
    echo "=== Test: resolve_region ==="
    
    local test_config
    test_config=$(setup_test_config)
    
    # Save original env vars
    local original_config="${AWS_CONFIG_FILE:-}"
    local original_region="${AWS_REGION:-}"
    local original_default_region="${AWS_DEFAULT_REGION:-}"
    local original_profile="${AWS_PROFILE:-}"
    
    export AWS_CONFIG_FILE="$test_config"
    unset AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE 2>/dev/null || true
    clear_profile_region_cache
    
    # Test 1: --region option takes priority
    local region
    region=$(resolve_region "--region eu-central-1 s3 ls")
    assert_equals "eu-central-1" "$region" "--region option should take priority"
    
    # Test 2: AWS_REGION env var
    export AWS_REGION="sa-east-1"
    region=$(resolve_region "s3 ls")
    assert_equals "sa-east-1" "$region" "AWS_REGION should be used when no --region"
    unset AWS_REGION
    
    # Test 3: AWS_DEFAULT_REGION env var
    export AWS_DEFAULT_REGION="ca-central-1"
    region=$(resolve_region "s3 ls")
    assert_equals "ca-central-1" "$region" "AWS_DEFAULT_REGION should be used"
    unset AWS_DEFAULT_REGION
    
    # Test 4: Profile from --profile option
    region=$(resolve_region "--profile dev s3 ls")
    assert_equals "us-west-2" "$region" "Profile region from --profile option"
    
    # Test 5: Profile from AWS_PROFILE env var
    export AWS_PROFILE="prod"
    region=$(resolve_region "s3 ls")
    assert_equals "ap-northeast-1" "$region" "Profile region from AWS_PROFILE"
    unset AWS_PROFILE
    
    # Test 6: Default profile when nothing specified
    region=$(resolve_region "s3 ls")
    assert_equals "us-east-1" "$region" "Default profile region"
    
    # Test 7: --region overrides everything
    export AWS_REGION="override-me"
    export AWS_PROFILE="prod"
    region=$(resolve_region "--region us-gov-west-1 s3 ls")
    assert_equals "us-gov-west-1" "$region" "--region should override all env vars"
    unset AWS_REGION AWS_PROFILE
    
    # Restore original env vars
    if [[ -n "$original_config" ]]; then
        export AWS_CONFIG_FILE="$original_config"
    else
        unset AWS_CONFIG_FILE
    fi
    [[ -n "$original_region" ]] && export AWS_REGION="$original_region"
    [[ -n "$original_default_region" ]] && export AWS_DEFAULT_REGION="$original_default_region"
    [[ -n "$original_profile" ]] && export AWS_PROFILE="$original_profile"
    
    cleanup_test_config "$test_config"
    clear_profile_region_cache
}

#######################################
# Test: Cache invalidation on config change
#######################################
test_cache_invalidation() {
    echo "=== Test: cache invalidation ==="
    
    local test_config_dir
    test_config_dir=$(mktemp -d)
    local test_config_file="$test_config_dir/config"
    
    # Create initial config
    cat > "$test_config_file" << 'EOF'
[default]
region = us-east-1
EOF
    
    local original_config="${AWS_CONFIG_FILE:-}"
    export AWS_CONFIG_FILE="$test_config_file"
    clear_profile_region_cache
    
    # Load initial cache
    local region
    region=$(get_profile_region "default")
    assert_equals "us-east-1" "$region" "Initial region should be us-east-1"
    
    # Wait a moment and update config
    sleep 1
    cat > "$test_config_file" << 'EOF'
[default]
region = eu-west-1
EOF
    
    # Cache should detect change and reload
    region=$(get_profile_region "default")
    assert_equals "eu-west-1" "$region" "Region should update after config change"
    
    # Restore
    if [[ -n "$original_config" ]]; then
        export AWS_CONFIG_FILE="$original_config"
    else
        unset AWS_CONFIG_FILE
    fi
    
    rm -rf "$test_config_dir"
    clear_profile_region_cache
}

#######################################
# Test: Return failure when no region found
#######################################
test_no_region_returns_failure() {
    echo "=== Test: no region returns failure ==="
    
    local test_config_dir
    test_config_dir=$(mktemp -d)
    local test_config_file="$test_config_dir/config"
    
    # Create config without region
    cat > "$test_config_file" << 'EOF'
[default]
output = json
EOF
    
    local original_config="${AWS_CONFIG_FILE:-}"
    local original_region="${AWS_REGION:-}"
    local original_default_region="${AWS_DEFAULT_REGION:-}"
    
    export AWS_CONFIG_FILE="$test_config_file"
    unset AWS_REGION AWS_DEFAULT_REGION 2>/dev/null || true
    clear_profile_region_cache
    
    # resolve_region should return failure (exit code 1) when no region found
    if resolve_region "s3 ls" > /dev/null 2>&1; then
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} Should return failure when no region found"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} Correctly returns failure when no region found"
    fi
    
    # Restore
    if [[ -n "$original_config" ]]; then
        export AWS_CONFIG_FILE="$original_config"
    else
        unset AWS_CONFIG_FILE
    fi
    [[ -n "$original_region" ]] && export AWS_REGION="$original_region"
    [[ -n "$original_default_region" ]] && export AWS_DEFAULT_REGION="$original_default_region"
    
    rm -rf "$test_config_dir"
    clear_profile_region_cache
}

#######################################
# Main
#######################################
main() {
    echo "Running profile_region.sh unit tests..."
    echo ""
    
    test_load_profile_region_cache
    echo ""
    
    test_get_profile_region
    echo ""
    
    test_resolve_region
    echo ""
    
    test_cache_invalidation
    echo ""
    
    test_no_region_returns_failure
    echo ""
    
    echo "================================"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo "================================"
    
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
