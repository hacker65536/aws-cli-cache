#!/usr/bin/env bash
#
# AWS CLI Cache Test Runner
# 
# すべてのテストスイートを実行するメインランナー
#

set -uo pipefail

# テスト設定
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# カラー出力
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# テスト結果
declare -i TOTAL_SUITES=0
declare -i PASSED_SUITES=0
declare -i FAILED_SUITES=0
declare -a FAILED_SUITE_NAMES=()

# ヘルプ表示
show_help() {
    cat << EOF
AWS CLI Cache Test Runner

Usage: $0 [OPTIONS] [TEST_SUITES...]

Options:
  -h, --help          Show this help message
  -v, --verbose       Verbose output
  -q, --quiet         Quiet mode (only show summary)
  --unit-only         Run only unit tests
  --integration-only  Run only integration tests
  --performance-only  Run only performance tests
  --no-integration    Skip integration tests
  --no-performance    Skip performance tests

Test Suites:
  unit                Unit tests (test_aws_cache.sh)
  integration         Integration tests (test_integration.sh)
  performance         Performance tests (test_performance.sh)

Examples:
  $0                          # Run all tests
  $0 unit                     # Run only unit tests
  $0 unit integration         # Run unit and integration tests
  $0 --no-integration         # Run all except integration tests
  $0 --performance-only       # Run only performance tests

EOF
}

# ログ関数
log_info() {
    [[ "${QUIET:-false}" != true ]] && echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

# テストスイート実行
run_test_suite() {
    local suite_name="$1"
    local script_path="$2"
    local description="$3"
    
    ((TOTAL_SUITES++))
    
    echo ""
    echo -e "${BOLD}=== Running $description ===${NC}"
    echo "Script: $script_path"
    echo ""
    
    local start_time end_time duration
    start_time=$(date +%s)
    
    if [[ "${VERBOSE:-false}" == true ]]; then
        if bash "$script_path"; then
            ((PASSED_SUITES++))
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            log_success "$description completed successfully (${duration}s)"
        else
            ((FAILED_SUITES++))
            FAILED_SUITE_NAMES+=("$suite_name")
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            log_error "$description failed (${duration}s)"
        fi
    else
        # 出力をキャプチャして結果のみ表示
        local output exit_code=0
        output=$(bash "$script_path" 2>&1) || exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            ((PASSED_SUITES++))
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            log_success "$description completed successfully (${duration}s)"
            
            # サマリー行のみ表示
            if [[ "${QUIET:-false}" != true ]]; then
                echo "$output" | grep -E "(Passed:|Failed:|Total:|✓ All.*passed|✗ Some.*failed)" || true
            fi
        else
            ((FAILED_SUITES++))
            FAILED_SUITE_NAMES+=("$suite_name")
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            log_error "$description failed (${duration}s)"
            
            # エラー出力を表示
            echo "$output" | tail -20
        fi
    fi
}

# 前提条件チェック
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # aws_cache.shの存在確認
    if [[ ! -f "$PROJECT_ROOT/aws_cache.sh" ]]; then
        log_error "aws_cache.sh not found in project root"
        exit 1
    fi
    
    # テストスクリプトの存在確認
    local missing_scripts=()
    
    [[ ! -f "$SCRIPT_DIR/test_aws_cache.sh" ]] && missing_scripts+=("test_aws_cache.sh")
    [[ ! -f "$SCRIPT_DIR/test_integration.sh" ]] && missing_scripts+=("test_integration.sh")
    [[ ! -f "$SCRIPT_DIR/test_performance.sh" ]] && missing_scripts+=("test_performance.sh")
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        log_error "Missing test scripts: ${missing_scripts[*]}"
        exit 1
    fi
    
    # 実行権限の確認と設定
    chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
    
    log_success "Prerequisites check completed"
}

# AWS CLI可用性チェック
check_aws_availability() {
    if command -v aws &> /dev/null; then
        if aws sts get-caller-identity &> /dev/null; then
            log_success "AWS CLI is available and configured"
            return 0
        else
            log_warning "AWS CLI found but not configured"
            return 1
        fi
    else
        log_warning "AWS CLI not found"
        return 1
    fi
}

# メイン実行関数
main() {
    local run_unit=true
    local run_integration=true
    local run_performance=true
    local specific_suites=()
    
    # 引数解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --unit-only)
                run_integration=false
                run_performance=false
                shift
                ;;
            --integration-only)
                run_unit=false
                run_performance=false
                shift
                ;;
            --performance-only)
                run_unit=false
                run_integration=false
                shift
                ;;
            --no-integration)
                run_integration=false
                shift
                ;;
            --no-performance)
                run_performance=false
                shift
                ;;
            unit|integration|performance)
                specific_suites+=("$1")
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 特定のスイートが指定された場合
    if [[ ${#specific_suites[@]} -gt 0 ]]; then
        run_unit=false
        run_integration=false
        run_performance=false
        
        for suite in "${specific_suites[@]}"; do
            case $suite in
                unit) run_unit=true ;;
                integration) run_integration=true ;;
                performance) run_performance=true ;;
            esac
        done
    fi
    
    echo -e "${BOLD}${BLUE}AWS CLI Cache Test Suite Runner${NC}"
    echo "Project: $(basename "$PROJECT_ROOT")"
    echo "Test Directory: $SCRIPT_DIR"
    echo ""
    
    check_prerequisites
    
    # AWS CLI可用性チェック
    local aws_available=false
    if check_aws_availability; then
        aws_available=true
    fi
    
    # テスト実行計画を表示
    echo ""
    log_info "Test execution plan:"
    [[ $run_unit == true ]] && echo "  ✓ Unit Tests"
    [[ $run_integration == true ]] && echo "  ✓ Integration Tests" && [[ $aws_available == false ]] && echo "    (AWS CLI not available - may skip some tests)"
    [[ $run_performance == true ]] && echo "  ✓ Performance Tests" && [[ $aws_available == false ]] && echo "    (AWS CLI not available - will skip)"
    
    # テスト実行
    local start_time
    start_time=$(date +%s)
    
    # Unit Tests
    if [[ $run_unit == true ]]; then
        run_test_suite "unit" "$SCRIPT_DIR/test_aws_cache.sh" "Unit Tests"
    fi
    
    # Integration Tests
    if [[ $run_integration == true ]]; then
        if [[ $aws_available == true ]]; then
            run_test_suite "integration" "$SCRIPT_DIR/test_integration.sh" "Integration Tests"
        else
            log_warning "Skipping integration tests - AWS CLI not available"
        fi
    fi
    
    # Performance Tests
    if [[ $run_performance == true ]]; then
        if [[ $aws_available == true ]]; then
            run_test_suite "performance" "$SCRIPT_DIR/test_performance.sh" "Performance Tests"
        else
            log_warning "Skipping performance tests - AWS CLI not available"
        fi
    fi
    
    # 結果サマリー
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    echo ""
    echo -e "${BOLD}=== Test Suite Summary ===${NC}"
    echo "Total suites run: $TOTAL_SUITES"
    echo -e "Passed: ${GREEN}$PASSED_SUITES${NC}"
    echo -e "Failed: ${RED}$FAILED_SUITES${NC}"
    echo "Total duration: ${duration}s"
    
    if [[ $FAILED_SUITES -gt 0 ]]; then
        echo ""
        echo -e "${RED}Failed test suites:${NC}"
        for suite in "${FAILED_SUITE_NAMES[@]}"; do
            echo -e "  ${RED}✗${NC} $suite"
        done
        echo ""
        echo -e "${RED}Some test suites failed. Please check the output above.${NC}"
        exit 1
    else
        echo ""
        echo -e "${GREEN}✓ All test suites passed successfully!${NC}"
        
        if [[ $aws_available == false ]]; then
            echo ""
            log_info "Note: Some tests were skipped due to AWS CLI not being available."
            log_info "To run all tests, please configure AWS CLI with 'aws configure'."
        fi
        
        exit 0
    fi
}

# スクリプトとして実行された場合
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi