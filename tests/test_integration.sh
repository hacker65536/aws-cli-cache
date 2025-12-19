#!/usr/bin/env bash
#
# AWS CLI Cache Integration Tests
# 
# 実際のAWS CLIとの統合テスト
# AWS CLIが設定されている環境でのみ実行
#

set -uo pipefail

# テスト設定
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TEST_CACHE_DIR="/tmp/aws_cache_integration_test_$$"

# カラー出力
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# テスト結果
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0
declare -a FAILED_TESTS=()

# 前提条件チェック
check_prerequisites() {
    echo -e "${BLUE}=== Checking Prerequisites ===${NC}"
    
    # AWS CLI存在チェック
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}✗ AWS CLI not found${NC}"
        echo "Please install AWS CLI to run integration tests"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} AWS CLI found: $(aws --version)"
    
    # AWS設定チェック
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}✗ AWS CLI not configured${NC}"
        echo "Please configure AWS CLI with 'aws configure' or set environment variables"
        exit 1
    fi
    
    local caller_identity
    caller_identity=$(aws sts get-caller-identity --output json)
    local account_id
    account_id=$(echo "$caller_identity" | jq -r '.Account')
    echo -e "${GREEN}✓${NC} AWS CLI configured (Account: $account_id)"
    
    # jq存在チェック
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠${NC} jq not found - some tests may be limited"
    else
        echo -e "${GREEN}✓${NC} jq found"
    fi
    
    echo ""
}

# テスト環境設定
setup_test_env() {
    # テスト用AWS設定を読み込み（存在する場合）
    if [[ -f "$SCRIPT_DIR/test-config.sh" ]]; then
        echo "Loading test configuration..."
        source "$SCRIPT_DIR/test-config.sh"
    fi
    
    export AWS_CACHE_DIR="$TEST_CACHE_DIR"
    export AWS_CACHE_TTL=30  # 統合テスト用に短いTTL
    export AWS_CACHE_VERIFY=false
    export AWS_CACHE_STATS=true
    
    mkdir -p "$TEST_CACHE_DIR"
    
    # aws_cache.shを読み込み
    source "$PROJECT_ROOT/aws_cache.sh"
    
    # 除外ルールキャッシュをリセット
    IS_EXCLUDES_LOADED=false
    CACHED_EXCLUDE_RULES=()
    
    echo "Integration test cache directory: $TEST_CACHE_DIR"
    echo "Cache TTL: $AWS_CACHE_TTL seconds"
    echo ""
}

# クリーンアップ
cleanup() {
    rm -rf "$TEST_CACHE_DIR" 2>/dev/null || true
}

# テストヘルパー関数
assert_success() {
    local test_name="$1"
    local exit_code="${2:-$?}"
    
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name (exit code: $exit_code)"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected to contain: '$needle'"
        echo "  Actual output: '$haystack'"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
    fi
}

measure_time() {
    local start end
    # macOS互換: Python を使用してミリ秒精度で測定
    if command -v python3 &> /dev/null; then
        start=$(python3 -c 'import time; print(int(time.time() * 1000))')
        "$@" > /dev/null 2>&1
        end=$(python3 -c 'import time; print(int(time.time() * 1000))')
        echo $((end - start))
    elif command -v python &> /dev/null; then
        start=$(python -c 'import time; print(int(time.time() * 1000))')
        "$@" > /dev/null 2>&1
        end=$(python -c 'import time; print(int(time.time() * 1000))')
        echo $((end - start))
    else
        # フォールバック: 秒単位
        start=$(date +%s)
        "$@" > /dev/null 2>&1
        end=$(date +%s)
        echo $(( (end - start) * 1000 ))
    fi
}

# 基本的なキャッシュ動作テスト
test_basic_caching() {
    echo -e "${BLUE}--- Basic Caching Tests ---${NC}"
    
    # キャッシュをクリア
    rm -rf "$TEST_CACHE_DIR"/* 2>/dev/null || true
    
    # 1回目の呼び出し（キャッシュミス）
    echo "Testing cache miss..."
    local output1
    output1=$(aws_cached --verbose sts get-caller-identity 2>&1)
    assert_contains "$output1" "[CACHE] Miss" "First call: cache miss detected"
    
    # 2回目の呼び出し（キャッシュヒット）
    echo "Testing cache hit..."
    local output2
    output2=$(aws_cached --verbose sts get-caller-identity 2>&1)
    assert_contains "$output2" "[CACHE] Hit" "Second call: cache hit detected"
    
    # 結果が同じであることを確認
    local result1 result2
    result1=$(aws_cached sts get-caller-identity --output json | jq -S .)
    result2=$(aws sts get-caller-identity --output json | jq -S .)
    
    if [[ "$result1" == "$result2" ]]; then
        echo -e "${GREEN}✓${NC} Cache returns same result as direct AWS CLI"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Cache returns same result as direct AWS CLI"
        FAILED_TESTS+=("Cache result consistency")
        ((TESTS_FAILED++))
    fi
}

# 強制リフレッシュテスト
test_force_refresh() {
    echo -e "${BLUE}--- Force Refresh Tests ---${NC}"
    
    # キャッシュを作成
    aws_cached sts get-caller-identity > /dev/null 2>&1
    
    # 強制リフレッシュ
    local output
    output=$(aws_cached --verbose --force-refresh sts get-caller-identity 2>&1)
    assert_contains "$output" "[CACHE] Force refresh" "Force refresh: cache deletion detected"
    assert_contains "$output" "[CACHE] Miss" "Force refresh: cache miss after deletion"
}

# キャッシュバイパステスト
test_cache_bypass() {
    echo -e "${BLUE}--- Cache Bypass Tests ---${NC}"
    
    # --no-cache オプション
    local output
    output=$(aws_cached --verbose --no-cache sts get-caller-identity 2>&1)
    assert_contains "$output" "[CACHE] Bypass" "No-cache option: cache bypassed"
    
    # 除外ルールキャッシュをリセットして再ロード
    IS_EXCLUDES_LOADED=false
    CACHED_EXCLUDE_RULES=()
    
    # 除外ルールによるバイパス（write操作）
    # create-db-cluster は除外ルールに該当するため、キャッシュされない
    output=$(aws_cached --verbose rds create-db-cluster --db-cluster-identifier test 2>&1 || true)
    if [[ "$output" == *"[CACHE] Excluded"* || "$output" == *"[CACHE] Bypass"* || "$output" == *"not cacheable"* ]]; then
        echo -e "${GREEN}✓${NC} Exclude rules: write operation bypassed"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Exclude rules: write operation bypassed"
        echo "  Output: $output"
        FAILED_TESTS+=("Exclude rules bypass")
        ((TESTS_FAILED++))
    fi
}

# 異なるパラメータでのキャッシュテスト
test_parameter_variations() {
    echo -e "${BLUE}--- Parameter Variation Tests ---${NC}"
    
    # 異なる出力形式
    aws_cached sts get-caller-identity --output json > /dev/null 2>&1
    aws_cached sts get-caller-identity --output text > /dev/null 2>&1
    
    # キャッシュファイルが別々に作成されることを確認
    local json_files text_files
    json_files=$(find "$TEST_CACHE_DIR" -path "*/json/*.cache" | wc -l | tr -d ' ')
    text_files=$(find "$TEST_CACHE_DIR" -path "*/text/*.cache" | wc -l | tr -d ' ')
    
    if [[ $json_files -gt 0 && $text_files -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} Different output formats create separate cache files"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Different output formats create separate cache files (json: $json_files, text: $text_files)"
        FAILED_TESTS+=("Output format separation")
        ((TESTS_FAILED++))
    fi
    
    # 異なるプロファイル（環境変数で設定）
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        local original_profile="$AWS_PROFILE"
        export AWS_PROFILE="test-profile-nonexistent"
        
        # 存在しないプロファイルでも異なるキャッシュパスが生成されることを確認
        local cache_file
        cache_file=$(get_cache_file 300 "sts" "get-caller-identity")
        assert_contains "$cache_file" "/test-profile-nonexistent/" "Different profile creates different cache path"
        
        export AWS_PROFILE="$original_profile"
    else
        echo -e "${YELLOW}⊘${NC} Profile variation test skipped (AWS_PROFILE not set)"
    fi
}

# パフォーマンステスト
test_performance() {
    echo -e "${BLUE}--- Performance Tests ---${NC}"
    
    # キャッシュをクリア
    rm -rf "$TEST_CACHE_DIR"/* 2>/dev/null || true
    
    echo "Measuring performance..."
    
    # 直接AWS CLI
    local direct_time
    direct_time=$(measure_time aws sts get-caller-identity)
    
    # 初回キャッシュ（ミス）
    local first_cache_time
    first_cache_time=$(measure_time aws_cached sts get-caller-identity)
    
    # 2回目キャッシュ（ヒット）
    local second_cache_time
    second_cache_time=$(measure_time aws_cached sts get-caller-identity)
    
    echo "  Direct AWS CLI:    ${direct_time}ms"
    echo "  First cached call: ${first_cache_time}ms (cache miss)"
    echo "  Second cached call: ${second_cache_time}ms (cache hit)"
    
    # キャッシュヒットが直接呼び出しより速いことを確認
    if [[ $second_cache_time -lt $direct_time ]]; then
        local speedup=$(( (direct_time * 100) / second_cache_time ))
        echo -e "${GREEN}✓${NC} Cache hit is faster (${speedup}% of direct call time)"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠${NC} Cache hit is not significantly faster (may be due to overhead or fast network)"
        # パフォーマンステストは失敗としてカウントしない（環境依存のため）
    fi
    
    # 初回呼び出しのオーバーヘッドが合理的であることを確認（2倍以下）
    if [[ $first_cache_time -le $((direct_time * 2)) ]]; then
        echo -e "${GREEN}✓${NC} Cache miss overhead is reasonable"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Cache miss overhead is too high"
        FAILED_TESTS+=("Cache miss overhead")
        ((TESTS_FAILED++))
    fi
}

# 並行実行テスト
test_concurrent_execution() {
    echo -e "${BLUE}--- Concurrent Execution Tests ---${NC}"
    
    # キャッシュをクリア
    rm -rf "$TEST_CACHE_DIR"/* 2>/dev/null || true
    
    echo "Testing concurrent cache access..."
    
    # 同じコマンドを並行実行
    aws_cached sts get-caller-identity > /tmp/concurrent1_$$ 2>&1 &
    local pid1=$!
    aws_cached sts get-caller-identity > /tmp/concurrent2_$$ 2>&1 &
    local pid2=$!
    aws_cached sts get-caller-identity > /tmp/concurrent3_$$ 2>&1 &
    local pid3=$!
    
    wait $pid1 $pid2 $pid3
    
    # 結果が同じであることを確認
    local result1 result2 result3
    result1=$(cat /tmp/concurrent1_$$ | grep -v "^\[CACHE\]" | jq -S . 2>/dev/null || cat /tmp/concurrent1_$$)
    result2=$(cat /tmp/concurrent2_$$ | grep -v "^\[CACHE\]" | jq -S . 2>/dev/null || cat /tmp/concurrent2_$$)
    result3=$(cat /tmp/concurrent3_$$ | grep -v "^\[CACHE\]" | jq -S . 2>/dev/null || cat /tmp/concurrent3_$$)
    
    if [[ "$result1" == "$result2" && "$result2" == "$result3" ]]; then
        echo -e "${GREEN}✓${NC} Concurrent execution returns consistent results"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Concurrent execution returns consistent results"
        FAILED_TESTS+=("Concurrent execution consistency")
        ((TESTS_FAILED++))
    fi
    
    # キャッシュファイルが作成されていることを確認
    local cache_count
    cache_count=$(find "$TEST_CACHE_DIR" -name "*.cache" -type f | wc -l | tr -d ' ')
    
    if [[ $cache_count -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} Concurrent execution creates cache files ($cache_count files)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Concurrent execution creates cache files"
        FAILED_TESTS+=("Concurrent cache creation")
        ((TESTS_FAILED++))
    fi
    
    # 一時ファイルをクリーンアップ
    rm -f /tmp/concurrent*_$$
}

# TTL期限切れテスト
test_ttl_expiration() {
    echo -e "${BLUE}--- TTL Expiration Tests ---${NC}"
    
    # TTL期限切れテスト用にキャッシュをクリア
    rm -rf "$TEST_CACHE_DIR"/* 2>/dev/null || true
    
    # 短いTTLでキャッシュを作成
    echo "Creating cache with short TTL..."
    aws_cached --cache-ttl 2 sts get-caller-identity > /dev/null 2>&1
    
    # すぐにキャッシュヒットすることを確認
    local output
    output=$(aws_cached --verbose --cache-ttl 2 sts get-caller-identity 2>&1)
    assert_contains "$output" "[CACHE] Hit" "Short TTL: immediate cache hit"
    
    # TTL期限切れを待つ
    echo "Waiting for TTL expiration..."
    sleep 3
    
    # 期限切れ後はキャッシュミスになることを確認
    output=$(aws_cached --verbose --cache-ttl 2 sts get-caller-identity 2>&1)
    assert_contains "$output" "[CACHE] Miss" "Short TTL: cache miss after expiration"
}

# エラーハンドリングテスト
test_error_handling() {
    echo -e "${BLUE}--- Error Handling Tests ---${NC}"
    
    # 存在しないサービス
    local exit_code=0
    aws_cached nonexistent-service describe-something 2>/dev/null || exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${GREEN}✓${NC} Error handling: nonexistent service returns error"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Error handling: nonexistent service returns error"
        FAILED_TESTS+=("Error handling: nonexistent service")
        ((TESTS_FAILED++))
    fi
    
    # エラーはキャッシュされないことを確認
    local cache_count_before cache_count_after
    cache_count_before=$(find "$TEST_CACHE_DIR" -name "*.cache" -type f | wc -l | tr -d ' ')
    
    aws_cached nonexistent-service describe-something 2>/dev/null || true
    
    cache_count_after=$(find "$TEST_CACHE_DIR" -name "*.cache" -type f | wc -l | tr -d ' ')
    
    if [[ $cache_count_before -eq $cache_count_after ]]; then
        echo -e "${GREEN}✓${NC} Error handling: errors are not cached"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Error handling: errors are not cached"
        FAILED_TESTS+=("Error handling: no error caching")
        ((TESTS_FAILED++))
    fi
}

# 統計機能テスト
test_statistics() {
    echo -e "${BLUE}--- Statistics Tests ---${NC}"
    
    # 統計ファイルが作成されることを確認
    aws_cached sts get-caller-identity > /dev/null 2>&1
    aws_cached sts get-caller-identity > /dev/null 2>&1  # キャッシュヒット
    
    local stats_file="$TEST_CACHE_DIR/.stats"
    
    if [[ -f "$stats_file" ]]; then
        echo -e "${GREEN}✓${NC} Statistics: stats file created"
        ((TESTS_PASSED++))
        
        # 統計内容を確認
        local hit_count miss_count
        hit_count=$(grep -c ",hit$" "$stats_file" 2>/dev/null || echo 0)
        miss_count=$(grep -c ",miss$" "$stats_file" 2>/dev/null || echo 0)
        
        echo "  Hits: $hit_count, Misses: $miss_count"
        
        if [[ $hit_count -gt 0 && $miss_count -gt 0 ]]; then
            echo -e "${GREEN}✓${NC} Statistics: records hits and misses"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗${NC} Statistics: records hits and misses"
            FAILED_TESTS+=("Statistics recording")
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${RED}✗${NC} Statistics: stats file created"
        FAILED_TESTS+=("Statistics file creation")
        ((TESTS_FAILED++))
    fi
}

# メイン実行関数
run_integration_tests() {
    echo -e "${BLUE}=== AWS CLI Cache Integration Test Suite ===${NC}"
    echo ""
    
    check_prerequisites
    setup_test_env
    
    test_basic_caching
    echo ""
    
    test_force_refresh
    echo ""
    
    test_cache_bypass
    echo ""
    
    test_parameter_variations
    echo ""
    
    test_performance
    echo ""
    
    test_concurrent_execution
    echo ""
    
    test_ttl_expiration
    echo ""
    
    test_error_handling
    echo ""
    
    test_statistics
    echo ""
    
    # テスト結果サマリー
    echo -e "${BLUE}=== Integration Test Summary ===${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Total:  $((TESTS_PASSED + TESTS_FAILED))"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo ""
        echo -e "${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
    fi
    
    echo ""
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All integration tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some integration tests failed${NC}"
        return 1
    fi
}

# トラップでクリーンアップ
trap cleanup EXIT

# スクリプトとして実行された場合
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_integration_tests
fi