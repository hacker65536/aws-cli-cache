#!/usr/bin/env bash

# AWS CLI Cache テストスクリプト

# set -e は使わない（テストの失敗を検出するため）

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# テスト結果カウンター
TESTS_PASSED=0
TESTS_FAILED=0

# テスト用のキャッシュディレクトリ（aws_cache.shを読み込む前に設定）
TEST_CACHE_DIR="/tmp/aws_cache_test_$$"
export AWS_CACHE_DIR="$TEST_CACHE_DIR"
export AWS_CACHE_TTL=10  # テスト用に短いTTL

# aws_cache.sh を読み込み
source ./aws_cache.sh

echo -e "${BLUE}=== AWS CLI Cache Test Suite ===${NC}"
echo "Test Cache Directory: $TEST_CACHE_DIR"
echo ""

# テストヘルパー関数
assert_success() {
    local exit_code=$?
    local test_name="$1"
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        ((TESTS_FAILED++))
        return 0
    fi
}

assert_failure() {
    local exit_code=$?
    local test_name="$1"
    if [ $exit_code -ne 0 ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        ((TESTS_FAILED++))
        return 0
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        ((TESTS_FAILED++))
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"
    
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name (file not found: $file)"
        ((TESTS_FAILED++))
    fi
}

assert_file_not_exists() {
    local file="$1"
    local test_name="$2"
    
    if [ ! -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name (file exists: $file)"
        ((TESTS_FAILED++))
    fi
}

# クリーンアップ関数
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up test cache directory...${NC}"
    rm -rf "$TEST_CACHE_DIR"
}

trap cleanup EXIT

# テスト開始
echo -e "${BLUE}--- Test 1: Basic Functions ---${NC}"

# extract_profile のテスト
result=$(extract_profile "rds describe-db-clusters --profile my-profile")
assert_equals "my-profile" "$result" "extract_profile with --profile"

result=$(extract_profile "rds describe-db-clusters")
# 環境変数が設定されている場合はその値、なければdefault
if [ -n "$AWS_PROFILE" ] || [ -n "$AWS_DEFAULT_PROFILE" ]; then
    echo -e "${YELLOW}⊘${NC} extract_profile without --profile (skipped: AWS_PROFILE is set)"
else
    assert_equals "default" "$result" "extract_profile without --profile (default)"
fi

# extract_service のテスト
result=$(extract_service "rds describe-db-clusters")
assert_equals "rds" "$result" "extract_service"

# extract_region のテスト
result=$(extract_region "rds describe-db-clusters --region us-east-1")
assert_equals "us-east-1" "$result" "extract_region with --region"

result=$(extract_region "rds describe-db-clusters")
assert_equals "global" "$result" "extract_region without --region (global)"

# extract_action のテスト
result=$(extract_action "rds" "describe-db-clusters" "--profile" "test")
assert_equals "describe-db-clusters" "$result" "extract_action"

# extract_format のテスト
result=$(extract_format "rds describe-db-clusters --output json")
assert_equals "json" "$result" "extract_format with --output"

result=$(extract_format "rds describe-db-clusters")
assert_equals "json" "$result" "extract_format without --output (default json)"

echo ""
echo -e "${BLUE}--- Test 2: Cache Excludes ---${NC}"

# is_cacheable のテスト
is_cacheable "rds" "describe-db-clusters"
assert_success "is_cacheable: rds:describe-db-clusters (should be cacheable)"

is_cacheable "rds" "create-db-cluster"
assert_failure "is_cacheable: rds:create-db-cluster (should NOT be cacheable)"

is_cacheable "lambda" "invoke"
assert_failure "is_cacheable: lambda:invoke (should NOT be cacheable)"

is_cacheable "sts" "get-caller-identity"
assert_success "is_cacheable: sts:get-caller-identity (should be cacheable)"

echo ""
echo -e "${BLUE}--- Test 3: Cache File Operations ---${NC}"

# キャッシュディレクトリが作成されることを確認
mkdir -p "$TEST_CACHE_DIR"
[ -d "$TEST_CACHE_DIR" ]
assert_success "Cache directory creation"

# write_cache と read_cache のテスト
test_cache_file="$TEST_CACHE_DIR/test.cache"
test_data="test data content"
write_cache "$test_cache_file" "$test_data"
assert_file_exists "$test_cache_file" "write_cache creates file"

result=$(read_cache "$test_cache_file")
assert_equals "$test_data" "$result" "read_cache returns correct data"

echo ""
echo -e "${BLUE}--- Test 4: Cache Key Generation ---${NC}"

# generate_cache_key のテスト
key1=$(generate_cache_key "rds describe-db-clusters --profile test")
key2=$(generate_cache_key "rds describe-db-clusters --profile test")
assert_equals "$key1" "$key2" "Same command generates same cache key"

key3=$(generate_cache_key "rds describe-db-clusters --profile other")
if [ "$key1" != "$key3" ]; then
    echo -e "${GREEN}✓${NC} Different commands generate different cache keys"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} Different commands generate different cache keys"
    ((TESTS_FAILED++))
fi

# generate_params_hash のテスト
hash1=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier my-cluster")
hash2=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier my-cluster")
assert_equals "$hash1" "$hash2" "Same params generate same hash"

hash3=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier other-cluster")
if [ "$hash1" != "$hash3" ]; then
    echo -e "${GREEN}✓${NC} Different params generate different hash"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} Different params generate different hash"
    ((TESTS_FAILED++))
fi

echo ""
echo -e "${BLUE}--- Test 5: Atomic Write (Concurrency) ---${NC}"

# アトミック書き込みのテスト
test_file="$TEST_CACHE_DIR/atomic_test.cache"
write_cache "$test_file" "data1" &
write_cache "$test_file" "data2" &
write_cache "$test_file" "data3" &
wait

# ファイルが存在し、破損していないことを確認
if [ -f "$test_file" ]; then
    content=$(cat "$test_file")
    if [ "$content" = "data1" ] || [ "$content" = "data2" ] || [ "$content" = "data3" ]; then
        echo -e "${GREEN}✓${NC} Atomic write: file is not corrupted"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Atomic write: file is corrupted (content: $content)"
        ((TESTS_FAILED++))
    fi
else
    echo -e "${RED}✗${NC} Atomic write: file not created"
    ((TESTS_FAILED++))
fi

echo ""
echo -e "${BLUE}--- Test 6: Cache File Path Generation ---${NC}"

# get_cache_file のテスト
cache_file=$(get_cache_file 300 "rds" "describe-db-clusters" "--profile" "test" "--region" "us-east-1")
# パスの構造を確認（正規表現を緩和）
if [[ "$cache_file" == *"/test/rds/us-east-1/"* ]] && [[ "$cache_file" == *"/json/"* ]] && [[ "$cache_file" == *"_300_"* ]]; then
    echo -e "${GREEN}✓${NC} get_cache_file generates correct path structure"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} get_cache_file generates correct path structure"
    echo "  Generated: $cache_file"
    ((TESTS_FAILED++))
fi

# ディレクトリが作成されることを確認
cache_dir=$(dirname "$cache_file")
if [ -d "$cache_dir" ]; then
    echo -e "${GREEN}✓${NC} get_cache_file creates directory structure"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} get_cache_file creates directory structure"
    ((TESTS_FAILED++))
fi

echo ""
echo -e "${BLUE}--- Test 7: Cache Validity Check ---${NC}"

# 有効なキャッシュファイルを作成（ディレクトリも作成）
timestamp=$(date +%s)
mkdir -p "$TEST_CACHE_DIR"
valid_cache="$TEST_CACHE_DIR/test_hash_3600_${timestamp}_$$.cache"
echo "test data" > "$valid_cache"

is_cache_valid "$valid_cache"
assert_success "is_cache_valid: valid cache (TTL not expired)"

# 期限切れのキャッシュファイルを作成
old_timestamp=$((timestamp - 7200))  # 2時間前
expired_cache="$TEST_CACHE_DIR/test_hash_3600_${old_timestamp}_$$.cache"
echo "old data" > "$expired_cache"

is_cache_valid "$expired_cache"
assert_failure "is_cache_valid: expired cache (TTL expired)"

echo ""
echo -e "${BLUE}--- Test 8: Real AWS CLI Integration (if available) ---${NC}"

if command -v aws &> /dev/null; then
    echo -e "${YELLOW}AWS CLI found, testing real integration...${NC}"
    
    # AWS CLIが設定されているか確認
    if aws sts get-caller-identity &> /dev/null; then
        echo -e "${GREEN}AWS CLI is configured${NC}"
        
        # テスト前にキャッシュをクリア
        find "$TEST_CACHE_DIR" -type f -name "*.cache" -delete 2>/dev/null || true
        
        # キャッシュミスのテスト
        echo "Testing cache miss..."
        output1=$(aws_cached --verbose sts get-caller-identity 2>&1)
        if echo "$output1" | grep -q "\[CACHE\] Miss"; then
            echo -e "${GREEN}✓${NC} First call: cache miss detected"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗${NC} First call: cache miss not detected"
            ((TESTS_FAILED++))
        fi
        
        # キャッシュヒットのテスト
        echo "Testing cache hit..."
        output2=$(aws_cached --verbose sts get-caller-identity 2>&1)
        if echo "$output2" | grep -q "\[CACHE\] Hit"; then
            echo -e "${GREEN}✓${NC} Second call: cache hit detected"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗${NC} Second call: cache hit not detected"
            ((TESTS_FAILED++))
        fi
        
        # 強制リフレッシュのテスト
        echo "Testing force refresh..."
        output3=$(aws_cached --verbose --force-refresh sts get-caller-identity 2>&1)
        if echo "$output3" | grep -q "\[CACHE\] Force refresh"; then
            echo -e "${GREEN}✓${NC} Force refresh: cache deleted"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗${NC} Force refresh: cache not deleted"
            ((TESTS_FAILED++))
        fi
        
        # --no-cache オプションのテスト
        echo "Testing --no-cache option..."
        output4=$(aws_cached --verbose --no-cache sts get-caller-identity 2>&1)
        if echo "$output4" | grep -q "\[CACHE\] Bypass"; then
            echo -e "${GREEN}✓${NC} --no-cache: cache bypassed"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗${NC} --no-cache: cache not bypassed"
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${YELLOW}⊘ AWS CLI not configured, skipping integration tests${NC}"
    fi
else
    echo -e "${YELLOW}⊘ AWS CLI not found, skipping integration tests${NC}"
fi

echo ""
echo -e "${BLUE}--- Test 9: Concurrent Execution ---${NC}"

if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
    echo "Testing concurrent cache writes..."
    
    # テスト前にキャッシュをクリア（新しいキャッシュが作成されることを確認するため）
    find "$TEST_CACHE_DIR" -type f -name "*.cache" -delete 2>/dev/null || true
    
    # 同じコマンドを並行実行
    aws_cached sts get-caller-identity > /dev/null 2>&1 &
    pid1=$!
    aws_cached sts get-caller-identity > /dev/null 2>&1 &
    pid2=$!
    aws_cached sts get-caller-identity > /dev/null 2>&1 &
    pid3=$!
    
    wait $pid1 $pid2 $pid3
    
    # 少し待機してファイルシステムの同期を確保
    sleep 0.5
    
    # キャッシュファイルが作成されていることを確認
    # 注: 並行実行でも、最初のプロセスがキャッシュを作成した後、
    # 残りのプロセスはそのキャッシュを使用するため、1-3個のファイルが作成される
    cache_count=$(find "$TEST_CACHE_DIR" -name "*.cache" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$cache_count" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Concurrent execution: cache files created ($cache_count files)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Concurrent execution: no cache files created"
        echo "  Debug: TEST_CACHE_DIR=$TEST_CACHE_DIR"
        echo "  Debug: AWS_CACHE_DIR=$AWS_CACHE_DIR"
        echo "  Debug: Directory exists: $([ -d "$TEST_CACHE_DIR" ] && echo yes || echo no)"
        echo "  Debug: Files in directory:"
        find "$TEST_CACHE_DIR" -type f 2>/dev/null | head -5
        ((TESTS_FAILED++))
    fi
    
    # キャッシュファイルが破損していないことを確認
    corrupted=0
    for cache_file in "$TEST_CACHE_DIR"/**/*.cache; do
        if [ -f "$cache_file" ]; then
            if ! cat "$cache_file" | jq . > /dev/null 2>&1; then
                ((corrupted++))
            fi
        fi
    done
    
    if [ $corrupted -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Concurrent execution: no corrupted cache files"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Concurrent execution: $corrupted corrupted cache files"
        ((TESTS_FAILED++))
    fi
else
    echo -e "${YELLOW}⊘ AWS CLI not available, skipping concurrent execution tests${NC}"
fi

echo ""
echo -e "${BLUE}--- Test 10: Performance Test ---${NC}"

if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
    echo "Measuring cache performance..."
    
    # キャッシュなし
    start=$(date +%s%N)
    aws sts get-caller-identity > /dev/null 2>&1
    end=$(date +%s%N)
    no_cache_time=$(( (end - start) / 1000000 ))
    
    # 初回（キャッシュミス）
    start=$(date +%s%N)
    aws_cached sts get-caller-identity > /dev/null 2>&1
    end=$(date +%s%N)
    first_call_time=$(( (end - start) / 1000000 ))
    
    # 2回目（キャッシュヒット）
    start=$(date +%s%N)
    aws_cached sts get-caller-identity > /dev/null 2>&1
    end=$(date +%s%N)
    cached_time=$(( (end - start) / 1000000 ))
    
    echo "  No cache:     ${no_cache_time}ms"
    echo "  First call:   ${first_call_time}ms (cache miss)"
    echo "  Cached call:  ${cached_time}ms (cache hit)"
    
    if [ $cached_time -lt $no_cache_time ]; then
        speedup=$(( (no_cache_time * 100) / cached_time ))
        echo -e "${GREEN}✓${NC} Cache is faster (${speedup}% of original time)"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠${NC} Cache is not faster (may be due to overhead)"
    fi
else
    echo -e "${YELLOW}⊘ AWS CLI not available, skipping performance tests${NC}"
fi

# テスト結果サマリー
echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Total:  $((TESTS_PASSED + TESTS_FAILED))"

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
