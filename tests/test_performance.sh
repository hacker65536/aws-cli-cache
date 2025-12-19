#!/usr/bin/env bash
#
# AWS CLI Cache Performance Tests
# 
# キャッシュシステムのパフォーマンスを詳細に測定
#

set -uo pipefail

# テスト設定
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TEST_CACHE_DIR="/tmp/aws_cache_perf_test_$$"

# カラー出力
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# パフォーマンス測定設定
readonly WARMUP_ITERATIONS=3
readonly MEASUREMENT_ITERATIONS=10

# 前提条件チェック
check_prerequisites() {
    echo -e "${BLUE}=== Performance Test Prerequisites ===${NC}"
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}✗ AWS CLI not found${NC}"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}✗ AWS CLI not configured${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓${NC} AWS CLI available and configured"
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
    export AWS_CACHE_TTL=3600
    export AWS_CACHE_VERIFY=false
    export AWS_CACHE_STATS=false  # パフォーマンステストでは統計を無効化
    
    mkdir -p "$TEST_CACHE_DIR"
    source "$PROJECT_ROOT/aws_cache.sh"
    
    echo "Performance test cache directory: $TEST_CACHE_DIR"
    echo "Warmup iterations: $WARMUP_ITERATIONS"
    echo "Measurement iterations: $MEASUREMENT_ITERATIONS"
    echo ""
}

# クリーンアップ
cleanup() {
    rm -rf "$TEST_CACHE_DIR" 2>/dev/null || true
}

# 時間測定ヘルパー（macOS互換）
# macOSではdate +%s%Nが使えないため、秒単位で測定
measure_time_ms() {
    local start end
    # Python を使用してミリ秒精度で測定（macOS/Linux両対応）
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

# 統計計算
calculate_stats() {
    local -a times=("$@")
    local sum=0
    local count=${#times[@]}
    
    # 平均
    for time in "${times[@]}"; do
        sum=$((sum + time))
    done
    local avg=$((sum / count))
    
    # 最小・最大
    local min=${times[0]}
    local max=${times[0]}
    for time in "${times[@]}"; do
        [[ $time -lt $min ]] && min=$time
        [[ $time -gt $max ]] && max=$time
    done
    
    # 標準偏差（簡易版）
    local variance_sum=0
    for time in "${times[@]}"; do
        local diff=$((time - avg))
        variance_sum=$((variance_sum + diff * diff))
    done
    local variance=$((variance_sum / count))
    local stddev=$(echo "sqrt($variance)" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
    
    echo "$avg $min $max $stddev"
}

# 基本的なキャッシュパフォーマンステスト
test_basic_cache_performance() {
    echo -e "${BLUE}--- Basic Cache Performance ---${NC}"
    
    # ウォームアップ
    echo "Warming up..."
    for ((i=1; i<=WARMUP_ITERATIONS; i++)); do
        aws sts get-caller-identity > /dev/null 2>&1
        aws_cached sts get-caller-identity > /dev/null 2>&1
    done
    
    # 直接AWS CLI測定
    echo "Measuring direct AWS CLI calls ($MEASUREMENT_ITERATIONS iterations)..."
    local -a direct_times=()
    for ((i=1; i<=MEASUREMENT_ITERATIONS; i++)); do
        echo -n "  [$i/$MEASUREMENT_ITERATIONS] "
        local time_ms
        time_ms=$(measure_time_ms aws sts get-caller-identity)
        direct_times+=("$time_ms")
        echo "${time_ms}ms"
    done
    
    # キャッシュミス測定
    echo "Measuring cache miss performance ($MEASUREMENT_ITERATIONS iterations)..."
    local -a miss_times=()
    for ((i=1; i<=MEASUREMENT_ITERATIONS; i++)); do
        echo -n "  [$i/$MEASUREMENT_ITERATIONS] "
        # キャッシュをクリア
        rm -rf "$TEST_CACHE_DIR"/* 2>/dev/null || true
        
        local time_ms
        time_ms=$(measure_time_ms aws_cached sts get-caller-identity)
        miss_times+=("$time_ms")
        echo "${time_ms}ms"
    done
    
    # キャッシュヒット測定
    echo "Measuring cache hit performance ($MEASUREMENT_ITERATIONS iterations)..."
    # キャッシュを作成
    aws_cached sts get-caller-identity > /dev/null 2>&1
    
    local -a hit_times=()
    for ((i=1; i<=MEASUREMENT_ITERATIONS; i++)); do
        echo -n "  [$i/$MEASUREMENT_ITERATIONS] "
        local time_ms
        time_ms=$(measure_time_ms aws_cached sts get-caller-identity)
        hit_times+=("$time_ms")
        echo "${time_ms}ms"
    done
    
    # 統計計算
    local direct_stats miss_stats hit_stats
    direct_stats=($(calculate_stats "${direct_times[@]}"))
    miss_stats=($(calculate_stats "${miss_times[@]}"))
    hit_stats=($(calculate_stats "${hit_times[@]}"))
    
    # 結果表示
    echo ""
    echo "Performance Results (milliseconds):"
    echo "                    Avg    Min    Max    StdDev"
    printf "Direct AWS CLI:   %6d %6d %6d %6d\n" "${direct_stats[@]}"
    printf "Cache Miss:       %6d %6d %6d %6d\n" "${miss_stats[@]}"
    printf "Cache Hit:        %6d %6d %6d %6d\n" "${hit_stats[@]}"
    
    # パフォーマンス比較
    local direct_avg=${direct_stats[0]}
    local miss_avg=${miss_stats[0]}
    local hit_avg=${hit_stats[0]}
    
    local miss_overhead=$((miss_avg * 100 / direct_avg))
    local hit_speedup=$((direct_avg * 100 / hit_avg))
    
    echo ""
    echo "Performance Analysis:"
    echo "  Cache miss overhead: ${miss_overhead}% of direct call"
    echo "  Cache hit speedup: ${hit_speedup}% faster than direct call"
    
    if [[ $hit_avg -lt $direct_avg ]]; then
        echo -e "  ${GREEN}✓ Cache provides performance benefit${NC}"
    else
        echo -e "  ${YELLOW}⚠ Cache overhead may be too high${NC}"
    fi
}

# 大量データのパフォーマンステスト
test_large_data_performance() {
    echo -e "${BLUE}--- Large Data Performance ---${NC}"
    
    # EC2インスタンス一覧（大きなレスポンス）
    if aws ec2 describe-instances --max-items 1 &> /dev/null; then
        echo "Testing with EC2 describe-instances (large response)..."
        
        # キャッシュミス
        rm -rf "$TEST_CACHE_DIR"/* 2>/dev/null || true
        local miss_time
        miss_time=$(measure_time_ms aws_cached ec2 describe-instances --max-items 50)
        
        # キャッシュヒット
        local hit_time
        hit_time=$(measure_time_ms aws_cached ec2 describe-instances --max-items 50)
        
        echo "  Large data cache miss: ${miss_time}ms"
        echo "  Large data cache hit:  ${hit_time}ms"
        
        if [[ $hit_time -lt $miss_time ]]; then
            local improvement=$((miss_time * 100 / hit_time))
            echo -e "  ${GREEN}✓ Cache improves large data performance (${improvement}% faster)${NC}"
        fi
    else
        echo -e "${YELLOW}⊘ EC2 access not available, skipping large data test${NC}"
    fi
}

# 並行実行パフォーマンステスト
test_concurrent_performance() {
    echo -e "${BLUE}--- Concurrent Execution Performance ---${NC}"
    
    local concurrent_levels=(1 2 4 8)
    
    for level in "${concurrent_levels[@]}"; do
        echo "Testing with $level concurrent processes..."
        
        # キャッシュをクリア
        rm -rf "$TEST_CACHE_DIR"/* 2>/dev/null || true
        
        local start_time end_time
        # macOS互換: Python を使用してミリ秒精度で測定
        if command -v python3 &> /dev/null; then
            start_time=$(python3 -c 'import time; print(int(time.time() * 1000))')
        else
            start_time=$(($(date +%s) * 1000))
        fi
        
        # 並行実行
        local -a pids=()
        for ((i=1; i<=level; i++)); do
            aws_cached sts get-caller-identity > /dev/null 2>&1 &
            pids+=($!)
        done
        
        # 全プロセスの完了を待つ
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
        
        if command -v python3 &> /dev/null; then
            end_time=$(python3 -c 'import time; print(int(time.time() * 1000))')
        else
            end_time=$(($(date +%s) * 1000))
        fi
        local total_time=$((end_time - start_time))
        
        echo "  $level processes: ${total_time}ms total"
        
        # キャッシュファイル数を確認
        local cache_files
        cache_files=$(find "$TEST_CACHE_DIR" -name "*.cache" -type f | wc -l | tr -d ' ')
        echo "  Cache files created: $cache_files"
    done
}

# キャッシュサイズとパフォーマンスの関係
test_cache_size_performance() {
    echo -e "${BLUE}--- Cache Size vs Performance ---${NC}"
    
    # 異なるサイズのキャッシュを作成
    local cache_sizes=(10 50 100 500)
    
    for size in "${cache_sizes[@]}"; do
        echo "Testing with $size cache entries..."
        
        # キャッシュをクリア
        rm -rf "$TEST_CACHE_DIR"/* 2>/dev/null || true
        
        # 複数の異なるコマンドでキャッシュを作成
        for ((i=1; i<=size; i++)); do
            aws_cached sts get-caller-identity --query "Account" --output text > /dev/null 2>&1 || true
            aws_cached sts get-caller-identity --query "UserId" --output text > /dev/null 2>&1 || true
            [[ $((i * 2)) -ge $size ]] && break
        done
        
        # キャッシュヒットのパフォーマンスを測定
        local hit_time
        hit_time=$(measure_time_ms aws_cached sts get-caller-identity --query "Account" --output text)
        
        local cache_files
        cache_files=$(find "$TEST_CACHE_DIR" -name "*.cache" -type f | wc -l | tr -d ' ')
        
        echo "  Cache entries: $cache_files, Hit time: ${hit_time}ms"
    done
}

# メモリ使用量測定
test_memory_usage() {
    echo -e "${BLUE}--- Memory Usage Analysis ---${NC}"
    
    if command -v ps &> /dev/null; then
        # プロセス開始前のメモリ使用量
        local initial_memory
        initial_memory=$(ps -o rss= -p $$ | tr -d ' ')
        
        # 大量のキャッシュ操作
        for ((i=1; i<=100; i++)); do
            aws_cached sts get-caller-identity --query "Account" --output text > /dev/null 2>&1 || true
            [[ $((i % 10)) -eq 0 ]] && echo -n "."
        done
        echo ""
        
        # プロセス終了時のメモリ使用量
        local final_memory
        final_memory=$(ps -o rss= -p $$ | tr -d ' ')
        
        local memory_diff=$((final_memory - initial_memory))
        
        echo "  Initial memory: ${initial_memory}KB"
        echo "  Final memory: ${final_memory}KB"
        echo "  Memory increase: ${memory_diff}KB"
        
        if [[ $memory_diff -lt 10000 ]]; then  # 10MB未満
            echo -e "  ${GREEN}✓ Memory usage is reasonable${NC}"
        else
            echo -e "  ${YELLOW}⚠ High memory usage detected${NC}"
        fi
    else
        echo -e "${YELLOW}⊘ ps command not available, skipping memory test${NC}"
    fi
}

# ディスク使用量とパフォーマンス
test_disk_performance() {
    echo -e "${BLUE}--- Disk Usage and Performance ---${NC}"
    
    # キャッシュディスクサイズ測定
    local initial_size
    initial_size=$(du -sk "$TEST_CACHE_DIR" 2>/dev/null | cut -f1 || echo 0)
    
    # 複数のキャッシュエントリを作成
    echo "Creating cache entries..."
    for ((i=1; i<=50; i++)); do
        aws_cached sts get-caller-identity --query "Account" --output text > /dev/null 2>&1 || true
        aws_cached sts get-caller-identity --query "UserId" --output text > /dev/null 2>&1 || true
        [[ $((i % 10)) -eq 0 ]] && echo -n "."
    done
    echo ""
    
    local final_size
    final_size=$(du -sk "$TEST_CACHE_DIR" 2>/dev/null | cut -f1 || echo 0)
    local size_diff=$((final_size - initial_size))
    
    local cache_files
    cache_files=$(find "$TEST_CACHE_DIR" -name "*.cache" -type f | wc -l | tr -d ' ')
    
    echo "  Cache files: $cache_files"
    echo "  Disk usage: ${size_diff}KB"
    
    if [[ $cache_files -gt 0 ]]; then
        local avg_file_size=$((size_diff / cache_files))
        echo "  Average file size: ${avg_file_size}KB"
    fi
    
    # キャッシュ検索パフォーマンス
    local search_time
    search_time=$(measure_time_ms find_valid_cache_file 3600 "sts" "get-caller-identity")
    echo "  Cache search time: ${search_time}ms"
}

# メイン実行関数
run_performance_tests() {
    echo -e "${BLUE}=== AWS CLI Cache Performance Test Suite ===${NC}"
    echo ""
    
    check_prerequisites
    setup_test_env
    
    test_basic_cache_performance
    echo ""
    
    test_large_data_performance
    echo ""
    
    test_concurrent_performance
    echo ""
    
    test_cache_size_performance
    echo ""
    
    test_memory_usage
    echo ""
    
    test_disk_performance
    echo ""
    
    echo -e "${BLUE}=== Performance Test Complete ===${NC}"
    echo "Cache directory: $TEST_CACHE_DIR"
    echo "Total cache files: $(find "$TEST_CACHE_DIR" -name "*.cache" -type f | wc -l | tr -d ' ')"
    echo "Total cache size: $(du -sh "$TEST_CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")"
}

# トラップでクリーンアップ
trap cleanup EXIT

# スクリプトとして実行された場合
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_performance_tests
fi