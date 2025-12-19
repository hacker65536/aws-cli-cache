#!/usr/bin/env bash
#
# AWS CLI Cache Test Suite
# 
# 包括的なテストスイートでaws_cache.shの全機能をテスト
#

set -uo pipefail

# テスト設定
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TEST_CACHE_DIR="/tmp/aws_cache_test_$$"
readonly TEST_CONFIG_DIR="/tmp/aws_cache_config_test_$$"

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

# テスト環境設定（トップレベルで実行）
export AWS_CACHE_DIR="$TEST_CACHE_DIR"
export AWS_CACHE_TTL=10
export AWS_CACHE_MAX_SIZE=1048576  # 1MB
export AWS_CACHE_MAX_FILES=100
export AWS_CACHE_VERIFY=false
export AWS_CACHE_STATS=true
export AWS_CACHE_EXCLUDE_CONFIG="$TEST_CONFIG_DIR/cache-exclude"
export XDG_CACHE_HOME="$(dirname "$TEST_CACHE_DIR")"
export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
export AWS_CACHE_SKIP_INIT=true  # 初期化をスキップ

mkdir -p "$TEST_CACHE_DIR" "$TEST_CONFIG_DIR"

# aws_cache.shをトップレベルで読み込み（declare -a がグローバルになるように）
source "$PROJECT_ROOT/aws_cache.sh"

# テスト環境設定関数（状態リセット用）
setup_test_env() {
    # 除外ルールキャッシュをリセット
    IS_EXCLUDES_LOADED=false
    CACHED_EXCLUDE_RULES=()
    
    # 設定を再初期化
    init_config
    ensure_cache_dir
}

# クリーンアップ
cleanup() {
    rm -rf "$TEST_CACHE_DIR" "$TEST_CONFIG_DIR" 2>/dev/null || true
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

assert_failure() {
    local test_name="$1"
    local exit_code="${2:-$?}"
    
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name (expected failure but succeeded)"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
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
        echo "  String '$haystack' does not contain '$needle'"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"
    
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name (file not found: $file)"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
    fi
}

assert_file_not_exists() {
    local file="$1"
    local test_name="$2"
    
    if [[ ! -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name (file exists: $file)"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
    fi
}

# テストスイート
test_parameter_extraction() {
    echo -e "${BLUE}--- Parameter Extraction Tests ---${NC}"
    
    # extract_profile
    local result
    result=$(extract_profile "rds describe-db-clusters --profile my-profile")
    assert_equals "my-profile" "$result" "extract_profile with --profile"
    
    result=$(extract_profile "rds describe-db-clusters")
    assert_equals "${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-default}}" "$result" "extract_profile without --profile"
    
    # extract_service
    result=$(extract_service "rds" "describe-db-clusters")
    assert_equals "rds" "$result" "extract_service basic"
    
    result=$(extract_service "--profile" "test" "rds" "describe-db-clusters")
    assert_equals "rds" "$result" "extract_service with global options"
    
    # extract_region
    result=$(extract_region "rds describe-db-clusters --region us-east-1")
    assert_equals "us-east-1" "$result" "extract_region with --region"
    
    result=$(extract_region "rds describe-db-clusters")
    assert_equals "${AWS_REGION:-${AWS_DEFAULT_REGION:-global}}" "$result" "extract_region without --region"
    
    # extract_action
    result=$(extract_action "rds" "rds" "describe-db-clusters" "--profile" "test")
    assert_equals "describe-db-clusters" "$result" "extract_action basic"
    
    # extract_format
    result=$(extract_format "rds describe-db-clusters --output json")
    assert_equals "json" "$result" "extract_format with --output json"
    
    result=$(extract_format "rds describe-db-clusters --output table")
    assert_equals "table" "$result" "extract_format with --output table"
    
    result=$(extract_format "rds describe-db-clusters")
    assert_equals "json" "$result" "extract_format default"
}

test_cache_excludes() {
    echo -e "${BLUE}--- Cache Exclude Tests ---${NC}"
    
    # デフォルト除外ルール
    if is_cacheable "rds" "describe-db-clusters"; then
        echo -e "${GREEN}✓${NC} is_cacheable: rds:describe-db-clusters (read operation)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} is_cacheable: rds:describe-db-clusters (read operation)"
        FAILED_TESTS+=("is_cacheable: rds:describe-db-clusters (read operation)")
        ((TESTS_FAILED++))
    fi
    
    if ! is_cacheable "rds" "create-db-cluster"; then
        echo -e "${GREEN}✓${NC} is_cacheable: rds:create-db-cluster (write operation)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} is_cacheable: rds:create-db-cluster (write operation) (expected failure but succeeded)"
        FAILED_TESTS+=("is_cacheable: rds:create-db-cluster (write operation)")
        ((TESTS_FAILED++))
    fi
    
    if ! is_cacheable "lambda" "invoke"; then
        echo -e "${GREEN}✓${NC} is_cacheable: lambda:invoke (execution operation)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} is_cacheable: lambda:invoke (execution operation) (expected failure but succeeded)"
        FAILED_TESTS+=("is_cacheable: lambda:invoke (execution operation)")
        ((TESTS_FAILED++))
    fi
    
    if is_cacheable "sts" "get-caller-identity"; then
        echo -e "${GREEN}✓${NC} is_cacheable: sts:get-caller-identity (read operation)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} is_cacheable: sts:get-caller-identity (read operation)"
        FAILED_TESTS+=("is_cacheable: sts:get-caller-identity (read operation)")
        ((TESTS_FAILED++))
    fi
    
    # カスタム除外ルール
    mkdir -p "$(dirname "$AWS_CACHE_EXCLUDE_CONFIG")"
    cat > "$AWS_CACHE_EXCLUDE_CONFIG" << 'EOF'
# Test exclude rules
cloudwatch:describe-alarms
s3:*
*:list-buckets
EOF
    
    # キャッシュをリロード
    IS_EXCLUDES_LOADED=false
    
    if ! is_cacheable "cloudwatch" "describe-alarms"; then
        echo -e "${GREEN}✓${NC} is_cacheable: custom exclude rule (exact match)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} is_cacheable: custom exclude rule (exact match) (expected failure but succeeded)"
        FAILED_TESTS+=("is_cacheable: custom exclude rule (exact match)")
        ((TESTS_FAILED++))
    fi
    
    if ! is_cacheable "s3" "list-objects"; then
        echo -e "${GREEN}✓${NC} is_cacheable: custom exclude rule (service wildcard)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} is_cacheable: custom exclude rule (service wildcard) (expected failure but succeeded)"
        FAILED_TESTS+=("is_cacheable: custom exclude rule (service wildcard)")
        ((TESTS_FAILED++))
    fi
    
    if ! is_cacheable "ec2" "list-buckets"; then
        echo -e "${GREEN}✓${NC} is_cacheable: custom exclude rule (action wildcard)"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} is_cacheable: custom exclude rule (action wildcard) (expected failure but succeeded)"
        FAILED_TESTS+=("is_cacheable: custom exclude rule (action wildcard)")
        ((TESTS_FAILED++))
    fi
    
    if is_cacheable "cloudwatch" "get-metric-statistics"; then
        echo -e "${GREEN}✓${NC} is_cacheable: not excluded by custom rules"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} is_cacheable: not excluded by custom rules"
        FAILED_TESTS+=("is_cacheable: not excluded by custom rules")
        ((TESTS_FAILED++))
    fi
}

test_hash_generation() {
    echo -e "${BLUE}--- Hash Generation Tests ---${NC}"
    
    # generate_cache_key
    local key1 key2 key3
    key1=$(generate_cache_key "rds describe-db-clusters --profile test")
    key2=$(generate_cache_key "rds describe-db-clusters --profile test")
    key3=$(generate_cache_key "rds describe-db-clusters --profile other")
    
    assert_equals "$key1" "$key2" "generate_cache_key: same command same key"
    
    if [[ "$key1" != "$key3" ]]; then
        echo -e "${GREEN}✓${NC} generate_cache_key: different command different key"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} generate_cache_key: different command different key"
        FAILED_TESTS+=("generate_cache_key: different command different key")
        ((TESTS_FAILED++))
    fi
    
    # generate_params_hash
    local hash1 hash2 hash3
    hash1=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier cluster1")
    hash2=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier cluster1")
    hash3=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier cluster2")
    
    assert_equals "$hash1" "$hash2" "generate_params_hash: same params same hash"
    
    if [[ "$hash1" != "$hash3" ]]; then
        echo -e "${GREEN}✓${NC} generate_params_hash: different params different hash"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} generate_params_hash: different params different hash"
        FAILED_TESTS+=("generate_params_hash: different params different hash")
        ((TESTS_FAILED++))
    fi
    
    # パラメータ除外のテスト（--region, --profile, --output は除外される）
    local hash_with_region hash_without_region
    hash_with_region=$(generate_params_hash "rds describe-db-clusters --region us-east-1 --db-cluster-identifier cluster1")
    hash_without_region=$(generate_params_hash "rds describe-db-clusters --db-cluster-identifier cluster1")
    
    if [[ "$hash_with_region" == "$hash_without_region" ]]; then
        echo -e "${GREEN}✓${NC} generate_params_hash: excludes --region"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} generate_params_hash: excludes --region"
        echo "  With region: '$hash_with_region'"
        echo "  Without region: '$hash_without_region'"
        FAILED_TESTS+=("generate_params_hash: excludes --region")
        ((TESTS_FAILED++))
    fi
}

test_cache_file_operations() {
    echo -e "${BLUE}--- Cache File Operations Tests ---${NC}"
    
    # write_cache と read_cache
    local test_file="$TEST_CACHE_DIR/test.cache"
    local test_data="test cache data"
    
    write_cache "$test_file" "$test_data"
    assert_file_exists "$test_file" "write_cache: creates file"
    
    local result
    result=$(read_cache "$test_file")
    assert_equals "$test_data" "$result" "read_cache: returns correct data"
    
    # 整合性チェック付き書き込み
    AWS_CACHE_VERIFY=true
    local verify_file="$TEST_CACHE_DIR/verify.cache"
    write_cache "$verify_file" "$test_data"
    assert_file_exists "$verify_file" "write_cache: creates file with verification"
    assert_file_exists "$verify_file.sha256" "write_cache: creates hash file"
    
    result=$(read_cache "$verify_file" true)
    assert_equals "$test_data" "$result" "read_cache: verification success"
    
    # ハッシュファイルを破損させる
    echo "invalid_hash" > "$verify_file.sha256"
    result=$(read_cache "$verify_file" true 2>/dev/null || echo "FAILED")
    assert_equals "FAILED" "$result" "read_cache: verification failure"
    
    AWS_CACHE_VERIFY=false
}

test_cache_path_generation() {
    echo -e "${BLUE}--- Cache Path Generation Tests ---${NC}"
    
    local cache_file
    cache_file=$(get_cache_file 300 "rds" "describe-db-clusters" "--profile" "test" "--region" "us-east-1")
    
    # パス構造の確認
    assert_contains "$cache_file" "/test/rds/us-east-1/" "get_cache_file: correct path structure"
    assert_contains "$cache_file" "/json/" "get_cache_file: includes output format"
    assert_contains "$cache_file" "_300_" "get_cache_file: includes TTL"
    
    # ディレクトリが作成されることを確認
    local cache_dir
    cache_dir=$(dirname "$cache_file")
    if [[ -d "$cache_dir" ]]; then
        echo -e "${GREEN}✓${NC} get_cache_file: creates directory structure"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} get_cache_file: creates directory structure"
        FAILED_TESTS+=("get_cache_file: creates directory structure")
        ((TESTS_FAILED++))
    fi
}

test_cache_validity() {
    echo -e "${BLUE}--- Cache Validity Tests ---${NC}"
    
    # 有効なキャッシュファイル（3フィールド形式: hash_ttl_pid）
    local valid_cache="$TEST_CACHE_DIR/test_hash_3600_$$.cache"
    mkdir -p "$(dirname "$valid_cache")"
    echo "test data" > "$valid_cache"
    
    is_cache_valid "$valid_cache"
    assert_success "is_cache_valid: valid cache file"
    
    # 期限切れキャッシュファイル（短いTTL + sleep で期限切れを作成）
    local expired_cache="$TEST_CACHE_DIR/expired_hash_1_$$.cache"
    echo "old data" > "$expired_cache"
    sleep 2  # TTL=1秒なので2秒待てば期限切れ
    
    if ! is_cache_valid "$expired_cache"; then
        echo -e "${GREEN}✓${NC} is_cache_valid: expired cache file"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} is_cache_valid: expired cache file (expected failure but succeeded)"
        FAILED_TESTS+=("is_cache_valid: expired cache file")
        ((TESTS_FAILED++))
    fi
    
    # 存在しないファイル
    if ! is_cache_valid "/nonexistent/file.cache"; then
        echo -e "${GREEN}✓${NC} is_cache_valid: nonexistent file"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} is_cache_valid: nonexistent file (expected failure but succeeded)"
        FAILED_TESTS+=("is_cache_valid: nonexistent file")
        ((TESTS_FAILED++))
    fi
}

test_cache_search() {
    echo -e "${BLUE}--- Cache Search Tests ---${NC}"
    
    # get_cache_file を使って正しいパスを取得し、キャッシュファイルを作成
    local valid_cache
    valid_cache=$(get_cache_file 3600 "sts" "get-caller-identity")
    echo '{"Account": "123456789012"}' > "$valid_cache"
    
    # find_valid_cache_file のテスト
    local found_cache
    found_cache=$(find_valid_cache_file 3600 "sts" "get-caller-identity")
    
    if [[ -n "$found_cache" && -f "$found_cache" ]]; then
        echo -e "${GREEN}✓${NC} find_valid_cache_file: finds valid cache"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} find_valid_cache_file: finds valid cache"
        FAILED_TESTS+=("find_valid_cache_file: finds valid cache")
        ((TESTS_FAILED++))
    fi
    
    # 期限切れファイルは見つからない（短いTTL + sleep で期限切れを作成）
    local expired_cache
    expired_cache=$(get_cache_file 1 "sts" "get-caller-identity" "--profile" "expired")
    echo '{"Account": "123456789012"}' > "$expired_cache"
    sleep 2  # TTL=1秒なので2秒待てば期限切れ
    
    found_cache=$(find_valid_cache_file 3600 "sts" "get-caller-identity" "--profile" "expired")
    
    if [[ -z "$found_cache" ]]; then
        echo -e "${GREEN}✓${NC} find_valid_cache_file: ignores expired cache"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} find_valid_cache_file: ignores expired cache"
        FAILED_TESTS+=("find_valid_cache_file: ignores expired cache")
        ((TESTS_FAILED++))
    fi
}

test_concurrent_operations() {
    echo -e "${BLUE}--- Concurrent Operations Tests ---${NC}"
    
    # 並行書き込みテスト
    local test_file="$TEST_CACHE_DIR/concurrent.cache"
    
    write_cache "$test_file" "data1" &
    write_cache "$test_file" "data2" &
    write_cache "$test_file" "data3" &
    wait
    
    # ファイルが存在し、有効なデータが含まれていることを確認
    if [[ -f "$test_file" ]]; then
        local content
        content=$(cat "$test_file")
        if [[ "$content" == "data1" || "$content" == "data2" || "$content" == "data3" ]]; then
            echo -e "${GREEN}✓${NC} concurrent write_cache: no corruption"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗${NC} concurrent write_cache: data corruption (content: $content)"
            FAILED_TESTS+=("concurrent write_cache: no corruption")
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${RED}✗${NC} concurrent write_cache: file not created"
        FAILED_TESTS+=("concurrent write_cache: file creation")
        ((TESTS_FAILED++))
    fi
}

test_cache_limits() {
    echo -e "${BLUE}--- Cache Limits Tests ---${NC}"
    
    # ファイル数制限のテスト（小さな値に設定）
    export AWS_CACHE_MAX_FILES=5
    CACHE_MAX_FILES=5  # グローバル変数も更新
    
    # 複数のキャッシュファイルを作成
    for i in {1..10}; do
        local cache_file="$TEST_CACHE_DIR/test_$i.cache"
        echo "data $i" > "$cache_file"
        sleep 0.1  # アクセス時刻に差をつける
    done
    
    # 初期ファイル数を確認
    local initial_count
    initial_count=$(find "$TEST_CACHE_DIR" -name "*.cache" -type f | wc -l | tr -d ' ')
    
    # check_cache_limits を強制実行（"force" パラメータで確率的チェックを回避）
    check_cache_limits "force"
    
    # ファイル数が制限以下になっていることを確認
    local file_count
    file_count=$(find "$TEST_CACHE_DIR" -name "*.cache" -type f | wc -l | tr -d ' ')
    
    if [[ $file_count -le $AWS_CACHE_MAX_FILES ]]; then
        echo -e "${GREEN}✓${NC} check_cache_limits: enforces file count limit"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} check_cache_limits: enforces file count limit (found $file_count files, limit $AWS_CACHE_MAX_FILES)"
        FAILED_TESTS+=("check_cache_limits: file count limit")
        ((TESTS_FAILED++))
    fi
}

test_statistics() {
    echo -e "${BLUE}--- Statistics Tests ---${NC}"
    
    # 統計記録のテスト
    export AWS_CACHE_STATS=true
    
    record_cache_hit
    record_cache_miss
    record_cache_hit
    
    # 少し待機してバックグラウンド処理を完了
    sleep 0.5
    
    local stats_file="$TEST_CACHE_DIR/.stats"
    assert_file_exists "$stats_file" "record_cache_*: creates stats file"
    
    if [[ -f "$stats_file" ]]; then
        local hit_count miss_count
        hit_count=$(grep -c ",hit$" "$stats_file" 2>/dev/null || echo 0)
        miss_count=$(grep -c ",miss$" "$stats_file" 2>/dev/null || echo 0)
        
        if [[ $hit_count -eq 2 && $miss_count -eq 1 ]]; then
            echo -e "${GREEN}✓${NC} statistics: correct hit/miss counts"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗${NC} statistics: correct hit/miss counts (hits: $hit_count, misses: $miss_count)"
            FAILED_TESTS+=("statistics: hit/miss counts")
            ((TESTS_FAILED++))
        fi
    fi
}

# メイン実行関数
run_tests() {
    echo -e "${BLUE}=== AWS CLI Cache Test Suite ===${NC}"
    echo "Test Cache Directory: $TEST_CACHE_DIR"
    echo "Test Config Directory: $TEST_CONFIG_DIR"
    echo ""
    
    setup_test_env
    
    test_parameter_extraction
    echo ""
    
    test_cache_excludes
    echo ""
    
    test_hash_generation
    echo ""
    
    test_cache_file_operations
    echo ""
    
    test_cache_path_generation
    echo ""
    
    test_cache_validity
    echo ""
    
    test_cache_search
    echo ""
    
    test_concurrent_operations
    echo ""
    
    test_cache_limits
    echo ""
    
    test_statistics
    echo ""
    
    # テスト結果サマリー
    echo -e "${BLUE}=== Test Summary ===${NC}"
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
        echo -e "${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# トラップでクリーンアップ
trap cleanup EXIT

# スクリプトとして実行された場合
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tests
fi