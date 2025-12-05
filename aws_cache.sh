#!/usr/bin/env bash
#
# AWS CLI Cache Layer
# Version: 3.0.0
#
# Reduces AWS API call frequency by caching CLI responses.
# Supports TTL-based expiration, LRU eviction, and integrity verification.
#
# Usage:
#   source aws_cache.sh
#   aws_cached rds describe-db-clusters
#
# Environment Variables:
#   AWS_CACHE_DIR       - Cache directory (default: ~/.cache/aws-cli)
#   AWS_CACHE_TTL       - Default TTL in seconds (default: 3600)
#   AWS_CACHE_MAX_SIZE  - Max cache size in bytes (default: 1GB)
#   AWS_CACHE_MAX_FILES - Max number of cache files (default: 10000)
#   AWS_CACHE_VERIFY    - Enable integrity check (default: false)
#   AWS_CACHE_STATS     - Enable statistics recording (default: false)

# XDG Base Directory仕様に従ったキャッシュディレクトリ
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_DIR="${AWS_CACHE_DIR:-$XDG_CACHE_HOME/aws-cli}"
CACHE_TTL="${AWS_CACHE_TTL:-3600}"  # デフォルト1時間

# キャッシュサイズ制限
CACHE_MAX_SIZE="${AWS_CACHE_MAX_SIZE:-1073741824}"  # デフォルト1GB (バイト単位)
CACHE_MAX_FILES="${AWS_CACHE_MAX_FILES:-10000}"     # デフォルト10,000ファイル

# XDG Base Directory仕様に従った設定ファイル
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_EXCLUDE_CONFIG="${AWS_CACHE_EXCLUDE_CONFIG:-$XDG_CONFIG_HOME/aws-cli/cache-exclude}"

# キャッシュディレクトリ作成
mkdir -p "$CACHE_DIR"

# キャッシュ除外ルール（デフォルト）
# 形式: "service:action" または "service:*" または "*:action"
declare -a DEFAULT_EXCLUDE_RULES=(
    # Write系アクション（作成・更新・削除）- キャッシュすべきでない
    # RDS
    "rds:create-db-cluster"
    "rds:create-db-instance"
    "rds:modify-db-cluster"
    "rds:modify-db-instance"
    "rds:delete-db-cluster"
    "rds:delete-db-instance"
    "rds:reboot-db-instance"
    "rds:start-db-cluster"
    "rds:stop-db-cluster"
    
    # EC2
    "ec2:run-instances"
    "ec2:start-instances"
    "ec2:stop-instances"
    "ec2:terminate-instances"
    "ec2:reboot-instances"
    "ec2:create-volume"
    "ec2:delete-volume"
    "ec2:attach-volume"
    "ec2:detach-volume"
    
    # S3
    "s3:put-object"
    "s3:delete-object"
    "s3:create-bucket"
    "s3:delete-bucket"
    "s3:put-bucket-policy"
    "s3:delete-bucket-policy"
    
    # Lambda
    "lambda:create-function"
    "lambda:update-function-code"
    "lambda:update-function-configuration"
    "lambda:delete-function"
    "lambda:invoke"
    "lambda:publish-version"
    
    # DynamoDB
    "dynamodb:create-table"
    "dynamodb:update-table"
    "dynamodb:delete-table"
    "dynamodb:put-item"
    "dynamodb:update-item"
    "dynamodb:delete-item"
    "dynamodb:batch-write-item"
    
    # IAM
    "iam:create-user"
    "iam:delete-user"
    "iam:create-role"
    "iam:delete-role"
    "iam:attach-role-policy"
    "iam:detach-role-policy"
    "iam:put-user-policy"
    "iam:delete-user-policy"
    
    # CloudFormation
    "cloudformation:create-stack"
    "cloudformation:update-stack"
    "cloudformation:delete-stack"
    
    # ECS
    "ecs:create-cluster"
    "ecs:delete-cluster"
    "ecs:create-service"
    "ecs:update-service"
    "ecs:delete-service"
    "ecs:run-task"
    "ecs:stop-task"
    
    # SQS
    "sqs:send-message"
    "sqs:send-message-batch"
    "sqs:delete-message"
    "sqs:delete-message-batch"
    "sqs:purge-queue"
    
    # SNS
    "sns:publish"
    "sns:create-topic"
    "sns:delete-topic"
    "sns:subscribe"
    "sns:unsubscribe"
    
    # Athena
    "athena:start-query-execution"
    "athena:stop-query-execution"
    "athena:create-named-query"
    "athena:delete-named-query"
    "athena:create-work-group"
    "athena:delete-work-group"
    "athena:update-work-group"
)

# キャッシュ除外ルールのキャッシュ（パフォーマンス最適化）
declare -a CACHED_EXCLUDE_RULES=()
IS_EXCLUDES_LOADED=false

#######################################
# Load cache exclude rules from config file.
# Globals:
#   IS_EXCLUDES_LOADED - Flag indicating if rules are loaded
#   CACHED_EXCLUDE_RULES - Cached rules array
#   DEFAULT_EXCLUDE_RULES - Default rules array
#   CACHE_EXCLUDE_CONFIG - Config file path
# Arguments:
#   None
# Outputs:
#   Exclude rules to stdout (one per line)
# Returns:
#   0 on success
#######################################
load_cache_excludes() {
    # 既に読み込み済みの場合はキャッシュを返す
    if [[ "${IS_EXCLUDES_LOADED}" == true ]]; then
        printf '%s\n' "${CACHED_EXCLUDE_RULES[@]}"
        return
    fi
    
    local -a excludes=("${DEFAULT_EXCLUDE_RULES[@]}")
    
    # 設定ファイルが存在する場合は読み込み
    if [[ -f "${CACHE_EXCLUDE_CONFIG}" ]]; then
        while IFS= read -r line; do
            # コメント行と空行をスキップ
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            excludes+=("$line")
        done < "$CACHE_EXCLUDE_CONFIG"
    fi
    
    # キャッシュに保存
    CACHED_EXCLUDE_RULES=("${excludes[@]}")
    IS_EXCLUDES_LOADED=true
    
    printf '%s\n' "${excludes[@]}"
}

#######################################
# Check if a service:action combination is cacheable.
# Globals:
#   None
# Arguments:
#   service - AWS service name (e.g., "rds")
#   action - AWS action name (e.g., "describe-db-clusters")
# Outputs:
#   None
# Returns:
#   0 if cacheable, 1 if not cacheable
#######################################
is_cacheable() {
    local service="$1"
    local action="$2"
    
    # 除外ルールを読み込み（互換性のある方法）
    local excludes=()
    while IFS= read -r line; do
        [[ -n "${line}" ]] && excludes+=("$line")
    done < <(load_cache_excludes)
    
    for rule in "${excludes[@]}"; do
        local rule_service="${rule%%:*}"
        local rule_action="${rule##*:}"
        
        # 完全一致
        if [[ "${rule_service}" == "${service}" ]] && [[ "${rule_action}" == "${action}" ]]; then
            return 1  # キャッシュしない
        fi
        
        # サービスのワイルドカード: service:*
        if [[ "${rule_service}" == "${service}" ]] && [[ "${rule_action}" == "*" ]]; then
            return 1
        fi
        
        # アクションのワイルドカード: *:action
        if [[ "${rule_service}" == "*" ]] && [[ "${rule_action}" == "${action}" ]]; then
            return 1
        fi
        
        # 完全ワイルドカード: *:*
        if [[ "${rule_service}" == "*" ]] && [[ "${rule_action}" == "*" ]]; then
            return 1
        fi
    done
    
    return 0  # キャッシュする
}

#######################################
# Extract AWS profile from command arguments.
# Globals:
#   AWS_PROFILE - AWS profile environment variable
#   AWS_DEFAULT_PROFILE - Alternative AWS profile variable
# Arguments:
#   Command line arguments
# Outputs:
#   Profile name to stdout
# Returns:
#   0 on success
#######################################
extract_profile() {
    local cmd="$*"
    if echo "$cmd" | grep -q -- "--profile"; then
        echo "$cmd" | grep -o -- "--profile [^ ]*" | awk '{print $2}'
    else
        # プロファイルが指定されていない場合は環境変数から取得
        echo "${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-default}}"
    fi
}

# サービス名を抽出（AWS CLIコマンドから）
extract_service() {
    # グローバルオプション（--profile, --region, --output等）をスキップして
    # 最初のサービス名を取得
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile|--region|--output|--endpoint-url|--no-verify-ssl|--no-paginate|--query|--cli-input-json|--cli-input-yaml|--generate-cli-skeleton)
                shift 2  # オプションと値をスキップ
                ;;
            --*)
                shift  # その他のフラグオプションをスキップ
                ;;
            *)
                # サービス名を見つけた
                echo "$1"
                return
                ;;
        esac
    done
}

# リージョンを抽出
extract_region() {
    local cmd="$*"
    if echo "$cmd" | grep -q -- "--region"; then
        echo "$cmd" | grep -o -- "--region [^ ]*" | awk '{print $2}'
    else
        # リージョンが指定されていない場合は環境変数から取得
        echo "${AWS_REGION:-${AWS_DEFAULT_REGION:-global}}"
    fi
}

# アクション（操作）を抽出
extract_action() {
    local service="$1"
    shift
    
    # サービス名の後の最初の非オプション引数を取得
    local found_service=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile|--region|--output|--endpoint-url|--no-verify-ssl|--no-paginate|--query|--cli-input-json|--cli-input-yaml|--generate-cli-skeleton)
                shift 2  # オプションと値をスキップ
                ;;
            --*)
                shift  # その他のフラグオプションをスキップ
                ;;
            *)
                if [[ "$found_service" == false ]]; then
                    # サービス名をスキップ
                    if [[ "$1" == "$service" ]]; then
                        found_service=true
                        shift
                    else
                        shift
                    fi
                else
                    # アクション名を見つけた
                    echo "$1"
                    return
                fi
                ;;
        esac
    done
}

# パラメータハッシュを生成（--region, --profile, --output を除く、--queryを含む）
# 最適化版: パイプを削減、Bash組み込み機能を使用
generate_params_hash() {
    local cmd="$*"
    
    # --region, --profile, --output を除外したパラメータを抽出（--queryは含める）
    # Bash組み込みの文字列置換を使用（sedより高速）
    local params="$cmd"
    params="${params//--region [^ ]*/}"
    params="${params//--profile [^ ]*/}"
    params="${params//--output [^ ]*/}"
    # 余分な空白を削除（Bash組み込み）
    params="${params//  / }"
    params="${params# }"
    params="${params% }"
    
    # ハッシュ化（短縮版: 最初の16文字、Gitコミットハッシュと同じ長さ）
    # ファイル名として安全な文字のみを使用
    local hash
    hash=$(echo -n "$params" | shasum -a 256 | cut -c1-16)
    # 不正な文字を置換（Bash組み込み）
    echo "${hash//[^a-zA-Z0-9]/_}"
}

# 出力形式を抽出
extract_format() {
    local cmd="$*"
    if echo "$cmd" | grep -q -- "--output"; then
        echo "$cmd" | grep -o -- "--output [^ ]*" | awk '{print $2}'
    else
        # デフォルトはjson
        echo "json"
    fi
}

# キャッシュキー生成（コマンドとパラメータからハッシュ生成）
# 最適化版: パイプを削減
generate_cache_key() {
    local cmd="$*"
    # 完全なハッシュ（64文字）を使用
    local hash
    hash=$(echo -n "$cmd" | shasum -a 256)
    # 最初のフィールドのみ取得（Bash組み込み）
    echo "${hash%% *}"
}

# 階層化されたキャッシュファイルパス取得
get_cache_file() {
    local cmd="$*"
    local ttl="${1:-$CACHE_TTL}"  # TTLを引数から取得
    shift  # TTLを除外
    
    local profile=$(extract_profile "$@")
    local service=$(extract_service "$@")
    local region=$(extract_region "$@")
    local action=$(extract_action "$service" "$@")
    local params_hash=$(generate_params_hash "$@")
    local output_format=$(extract_format "$@")
    local cache_key=$(generate_cache_key "$@")
    
    # ディレクトリ構造: profile/service/region/action/params_hash/output_format/
    # 最適化版: パス構築を一度に実行
    local cache_path="$CACHE_DIR/$profile"
    
    # 第2層: サービス
    [[ -n "${service}" ]] && cache_path="$cache_path/$service"
    
    # 第3層: リージョン
    [[ -n "${region}" ]] && cache_path="$cache_path/$region"
    
    # 第4層: アクション
    [[ -n "${action}" ]] && cache_path="$cache_path/$action"
    
    # 第5層: パラメータハッシュ（--queryを含む）
    cache_path="$cache_path/$params_hash"
    
    # 第6層: 出力形式
    cache_path="$cache_path/$output_format"
    
    # ディレクトリ作成（最適化: -p は冪等なので毎回実行しても安全、エラー処理簡略化）
    mkdir -p "$cache_path" 2>/dev/null || true
    
    # ファイル名: hash_ttl_timestamp_pid.cache（並行実行対策でPIDを追加）
    local timestamp=$(date +%s)
    echo "$cache_path/${cache_key}_${ttl}_${timestamp}_$$.cache"
}

# 既存のキャッシュファイルを検索（TTL考慮）
# 最適化版: ディレクトリ内の最新ファイルのみチェック（全ファイルスキャンを回避）
find_valid_cache_file() {
    local cmd="$*"
    local ttl="${1:-$CACHE_TTL}"
    shift
    
    local profile=$(extract_profile "$@")
    local service=$(extract_service "$@")
    local region=$(extract_region "$@")
    local action=$(extract_action "$service" "$@")
    local params_hash=$(generate_params_hash "$@")
    local output_format=$(extract_format "$@")
    local cache_key=$(generate_cache_key "$@")
    
    # キャッシュディレクトリパス
    local cache_path="$CACHE_DIR/$profile/$service/$region/$action/$params_hash/$output_format"
    
    if [[ ! -d "${cache_path}" ]]; then
        return 1
    fi
    
    # 現在時刻（1回のみ取得）
    local current_time=$(date +%s)
    
    # 最新のキャッシュファイルのみチェック（最適化: 全ファイルループを回避）
    # ls -t でタイムスタンプ順にソート、最新の1ファイルのみ処理
    local latest_file
    latest_file=$(ls -t "$cache_path/${cache_key}_"*.cache 2>/dev/null | head -n 1)
    
    if [[ -z "$latest_file" ]] || [[ ! -f "$latest_file" ]]; then
        return 1
    fi
    
    # ファイル名から TTL と timestamp を抽出
    local filename=$(basename "$latest_file")
    # hash_ttl_timestamp_pid.cache の形式
    # 正規表現で最後の3つのフィールドを抽出
    if [[ "$filename" =~ _([0-9]+)_([0-9]+)_([0-9]+)\.cache$ ]]; then
        local file_ttl="${BASH_REMATCH[1]}"
        local file_timestamp="${BASH_REMATCH[2]}"
    else
        return 1
    fi
    
    # 有効期限チェック: timestamp + ttl > current_time
    local expiry_time=$((file_timestamp + file_ttl))
    
    if [[ ${expiry_time} -gt ${current_time} ]]; then
        # 有効なキャッシュが見つかった
        echo "$latest_file"
        return 0
    fi
    
    # 有効なキャッシュが見つからなかった
    return 1
}

# キャッシュの有効性チェック（ファイル名ベース）
is_cache_valid() {
    local cache_file="$1"
    
    if [[ ! -f "${cache_file}" ]]; then
        return 1
    fi
    
    # ファイル名から TTL と timestamp を抽出
    local filename=$(basename "$cache_file")
    # hash_ttl_timestamp_pid.cache の形式
    # 正規表現で最後の3つのフィールドを抽出
    if [[ "$filename" =~ _([0-9]+)_([0-9]+)_([0-9]+)\.cache$ ]]; then
        local file_ttl="${BASH_REMATCH[1]}"
        local file_timestamp="${BASH_REMATCH[2]}"
    else
        return 1
    fi
    
    # 現在時刻
    local current_time=$(date +%s)
    
    # 有効期限チェック: timestamp + ttl > current_time
    local expiry_time=$((file_timestamp + file_ttl))
    
    if [[ ${expiry_time} -gt ${current_time} ]]; then
        return 0
    else
        return 1
    fi
}

#######################################
# Read data from cache file with optional integrity check.
# Globals:
#   None
# Arguments:
#   cache_file - Path to cache file
#   verify - Enable integrity check (optional, default: false)
# Outputs:
#   Cache content to stdout
# Returns:
#   0 on success, 1 on failure or integrity check failed
#######################################
read_cache() {
    local cache_file="$1"
    local verify="${2:-false}"  # 整合性チェックフラグ
    
    # 整合性チェックが有効な場合
    if [[ "${verify}" == true ]] && [[ -f "${cache_file}.sha256" ]]; then
        local stored_hash
        stored_hash=$(cat "${cache_file}.sha256" 2>/dev/null)
        local actual_hash
        actual_hash=$(shasum -a 256 "$cache_file" 2>/dev/null | cut -d' ' -f1)
        
        if [[ "${stored_hash}" != "${actual_hash}" ]]; then
            # ハッシュが一致しない場合はキャッシュを削除
            rm -f "$cache_file" "${cache_file}.sha256" 2>/dev/null
            return 1
        fi
    fi
    
    cat "$cache_file"
}

#######################################
# Write data to cache file with atomic operation.
# Globals:
#   AWS_CACHE_VERIFY - Enable integrity check
# Arguments:
#   cache_file - Path to cache file
#   data - Data to write
# Outputs:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
write_cache() {
    local cache_file="$1"
    local data="$2"
    local temp_file="${cache_file}.tmp.$$"
    
    # キャッシュサイズチェック（書き込み前）
    check_cache_limits
    
    # 一時ファイルに書き込み
    echo "$data" > "$temp_file"
    
    # 整合性チェック用のハッシュを生成（オプション）
    if [[ "${AWS_CACHE_VERIFY:-false}" == true ]]; then
        shasum -a 256 "$temp_file" 2>/dev/null | cut -d' ' -f1 > "${temp_file}.sha256"
    fi
    
    # アトミックに移動（既存ファイルがあっても上書き）
    mv -f "$temp_file" "$cache_file" 2>/dev/null || {
        # 失敗した場合は一時ファイルを削除
        rm -f "$temp_file" "${temp_file}.sha256"
        return 1
    }
    
    # ハッシュファイルも移動
    if [[ -f "${temp_file}.sha256" ]]; then
        mv -f "${temp_file}.sha256" "${cache_file}.sha256" 2>/dev/null
    fi
}

#######################################
# Check and enforce cache size limits using LRU eviction.
# 最適化版: 確率的チェック（1%の確率）でパフォーマンス向上
# Globals:
#   CACHE_DIR - Cache directory path
#   CACHE_MAX_FILES - Maximum number of cache files
#   CACHE_MAX_SIZE - Maximum cache size in bytes
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 on success
#######################################
check_cache_limits() {
    # 確率的チェック: 1%の確率でのみ実行（パフォーマンス最適化）
    # 大規模バッチ処理で約4分削減
    [[ $((RANDOM % 100)) -ne 0 ]] && return 0
    
    # ファイル数チェック（高速化: find -quit で早期終了可能性）
    local file_count
    file_count=$(find "$CACHE_DIR" -type f -name "*.cache" 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$file_count" -ge "$CACHE_MAX_FILES" ]; then
        # LRU削除: 最も古いアクセス時刻のファイルを削除（macOS互換）
        local files_to_delete=$((file_count - CACHE_MAX_FILES + 100))  # 余裕を持って削除
        
        # macOS互換: ls -tuでアクセス時刻順にソート
        find "$CACHE_DIR" -type f -name "*.cache" 2>/dev/null | \
            xargs ls -tu 2>/dev/null | \
            tail -n "$files_to_delete" | \
            while IFS= read -r file; do
                [ -f "$file" ] && rm -f "$file" 2>/dev/null
            done
    fi
    
    # ディスク使用量チェック（macOS互換: du -sk）
    local cache_size
    cache_size=$(du -sk "$CACHE_DIR" 2>/dev/null | cut -f1)
    local max_size_kb=$((CACHE_MAX_SIZE / 1024))
    
    if [[ -n "$cache_size" ]] && [ "$cache_size" -ge "$max_size_kb" ]; then
        # LRU削除: サイズが制限以下になるまで削除
        local target_size_kb=$((max_size_kb * 80 / 100))  # 80%まで削減
        
        # アクセス時刻順にファイルを取得して削除
        find "$CACHE_DIR" -type f -name "*.cache" 2>/dev/null | \
            xargs ls -tu 2>/dev/null | \
            while IFS= read -r file; do
                [ -f "$file" ] && rm -f "$file" 2>/dev/null
                cache_size=$(du -sk "$CACHE_DIR" 2>/dev/null | cut -f1)
                [ "$cache_size" -lt "$target_size_kb" ] && break
            done
    fi
}

#######################################
# Execute AWS CLI command with caching support.
# Globals:
#   CACHE_TTL - Default TTL for cache entries
#   CACHE_DIR - Cache directory path
#   AWS_CACHE_VERIFY - Integrity check flag
#   AWS_CACHE_STATS - Statistics recording flag
# Arguments:
#   --cache-ttl <seconds> - Override default TTL
#   --force-refresh - Ignore cache and refresh
#   --no-cache - Bypass cache for this call
#   --verbose - Show cache hit/miss info
#   AWS CLI command and arguments
# Outputs:
#   AWS CLI command output to stdout
#   Cache status messages to stderr (if --verbose)
# Returns:
#   AWS CLI exit code
#######################################
aws_cached() {
    local ttl="$CACHE_TTL"
    local force_refresh=false
    local verbose=false
    local no_cache=false
    
    # オプション解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cache-ttl)
                ttl="$2"
                shift 2
                ;;
            --force-refresh)
                force_refresh=true
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --no-cache)
                no_cache=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    # サービスとアクションを抽出
    local service=$(extract_service "$@")
    local action=$(extract_action "$service" "$@")
    
    # キャッシュ対象かチェック
    if ! is_cacheable "$service" "$action"; then
        [ "$verbose" = true ] && echo "[CACHE] Excluded: $service:$action (not cacheable)" >&2
        no_cache=true
    fi
    
    # --no-cache オプションまたは除外ルールに該当する場合
    if [[ "$no_cache" == true ]]; then
        [ "$verbose" = true ] && echo "[CACHE] Bypass: Executing AWS CLI without cache" >&2
        aws "$@"
        return $?
    fi
    
    # 既存の有効なキャッシュを検索
    local cache_file=$(find_valid_cache_file "$ttl" "$@")
    
    # 強制リフレッシュの場合は既存キャッシュを削除
    if [[ "$force_refresh" == true ]]; then
        if [[ -n "$cache_file" ]] && [ -f "$cache_file" ]; then
            rm -f "$cache_file"
            [ "$verbose" = true ] && echo "[CACHE] Force refresh: deleted $cache_file" >&2
        fi
        cache_file=""
    fi
    
    # キャッシュヒット
    if [[ -n "$cache_file" ]] && is_cache_valid "$cache_file"; then
        # 有効期限情報を表示（verbose時のみ）
        if [[ "$verbose" == true ]]; then
            echo "[CACHE] Hit: $cache_file" >&2
            local filename=$(basename "$cache_file")
            # 正規表現で最後の3つのフィールドを抽出
            if [[ "$filename" =~ _([0-9]+)_([0-9]+)_([0-9]+)\.cache$ ]]; then
                local file_ttl="${BASH_REMATCH[1]}"
                local file_timestamp="${BASH_REMATCH[2]}"
                # date +%s はverbose時のみ実行（最適化: 2-5ms/回削減）
                local current_time=$(date +%s)
                local age=$((current_time - file_timestamp))
                local remaining=$((file_ttl - age))
                echo "[CACHE] Age: ${age}s, Remaining: ${remaining}s, TTL: ${file_ttl}s" >&2
            fi
        fi
        
        # 統計情報を記録（オプション）
        record_cache_hit
        
        read_cache "$cache_file" "${AWS_CACHE_VERIFY:-false}"
        return 0
    fi
    
    # キャッシュミス - AWS CLI実行
    [ "$verbose" = true ] && echo "[CACHE] Miss: Executing AWS CLI" >&2
    
    # 標準出力と標準エラー出力を分離してキャプチャ
    local temp_stdout=$(mktemp)
    local temp_stderr=$(mktemp)
    
    aws "$@" > "$temp_stdout" 2> "$temp_stderr"
    local exit_code=$?
    
    local result
    result=$(cat "$temp_stdout")
    local error_output
    error_output=$(cat "$temp_stderr")
    
    # 一時ファイルを削除
    rm -f "$temp_stdout" "$temp_stderr"
    
    if [ $exit_code -eq 0 ]; then
        # 統計情報を記録（オプション）
        record_cache_miss
        
        # 新しいキャッシュファイルを作成
        local new_cache_file
        new_cache_file=$(get_cache_file "$ttl" "$@")
        if write_cache "$new_cache_file" "$result"; then
            [ "$verbose" = true ] && echo "[CACHE] Saved to: $new_cache_file (TTL: ${ttl}s)" >&2
        else
            [ "$verbose" = true ] && echo "[CACHE] Warning: Failed to write cache file" >&2
        fi
        echo "$result"
    else
        [ "$verbose" = true ] && echo "[CACHE] Error: AWS CLI failed with exit code $exit_code" >&2
        # エラー出力を標準エラーに出力
        [ -n "$error_output" ] && echo "$error_output" >&2
        return $exit_code
    fi
}

# 統計情報を記録（キャッシュヒット）
# 最適化版: バックグラウンドで非同期実行、ファイルロック競合を回避
record_cache_hit() {
    # 統計記録が無効の場合は何もしない
    [[ "${AWS_CACHE_STATS:-false}" != true ]] && return 0
    
    local stats_file="$CACHE_DIR/.stats"
    local timestamp=$(date +%s)
    # バックグラウンドで非同期実行（並列実行時の競合解消）
    (echo "$timestamp,hit" >> "$stats_file" 2>/dev/null) &
}

# 統計情報を記録（キャッシュミス）
# 最適化版: バックグラウンドで非同期実行、ファイルロック競合を回避
record_cache_miss() {
    # 統計記録が無効の場合は何もしない
    [[ "${AWS_CACHE_STATS:-false}" != true ]] && return 0
    
    local stats_file="$CACHE_DIR/.stats"
    local timestamp=$(date +%s)
    # バックグラウンドで非同期実行（並列実行時の競合解消）
    (echo "$timestamp,miss" >> "$stats_file" 2>/dev/null) &
}

#######################################
# Clean expired cache files.
# Globals:
#   CACHE_DIR - Cache directory path
# Arguments:
#   None
# Outputs:
#   Cleanup statistics to stdout
# Returns:
#   0 on success
#######################################
clean_expired_cache() {
    echo "=== Cleaning Expired Cache Files ==="
    local current_time
    current_time=$(date +%s)
    local count=0
    local freed_size=0
    
    while IFS= read -r -d '' cache_file; do
        local filename
        filename=$(basename "$cache_file")
        # hash_ttl_timestamp_pid.cache の形式
        if [[ "${filename}" =~ ^(.+)_([0-9]+)_([0-9]+)_([0-9]+)\.cache$ ]]; then
            local file_ttl="${BASH_REMATCH[2]}"
            local file_timestamp="${BASH_REMATCH[3]}"
            local expiry_time=$((file_timestamp + file_ttl))
            
            if [[ ${expiry_time} -le ${current_time} ]]; then
                # 期限切れ
                local file_size
                file_size=$(du -k "$cache_file" | cut -f1)
                rm -f "$cache_file"
                ((count++))
                ((freed_size+=file_size))
            fi
        fi
    done < <(find "$CACHE_DIR" -type f -name "*.cache" -print0)
    
    echo "Removed ${count} expired cache files"
    echo "Freed space: ${freed_size}KB"
    
    # 空のディレクトリを削除
    find "$CACHE_DIR" -type d -empty -delete 2>/dev/null
}

#######################################
# Display cache hit/miss metrics.
# Globals:
#   CACHE_DIR - Cache directory path
# Arguments:
#   None
# Outputs:
#   Metrics to stdout
# Returns:
#   0 on success
#######################################
show_cache_metrics() {
    local stats_file="$CACHE_DIR/.stats"
    
    echo "=== Cache Metrics ==="
    echo ""
    
    if [[ ! -f "$stats_file" ]]; then
        echo "No metrics available. Enable with: export AWS_CACHE_STATS=true"
        return
    fi
    
    local total_hits
    total_hits=$(grep -c ",hit$" "$stats_file" 2>/dev/null)
    total_hits=${total_hits:-0}
    local total_misses
    total_misses=$(grep -c ",miss$" "$stats_file" 2>/dev/null)
    total_misses=${total_misses:-0}
    local total=$((total_hits + total_misses))
    
    if [ $total -eq 0 ]; then
        echo "No data recorded yet"
        return
    fi
    
    local hit_rate=$((total_hits * 100 / total))
    
    echo "Total requests: $total"
    echo "Cache hits: $total_hits"
    echo "Cache misses: $total_misses"
    echo "Hit rate: ${hit_rate}%"
    echo ""
    
    # 最近24時間の統計
    local day_ago=$(($(date +%s) - 86400))
    local recent_hits
    recent_hits=$(awk -F, -v cutoff="$day_ago" '$1 >= cutoff && $2 == "hit"' "$stats_file" 2>/dev/null | wc -l | tr -d ' ')
    recent_hits=${recent_hits:-0}
    local recent_misses
    recent_misses=$(awk -F, -v cutoff="$day_ago" '$1 >= cutoff && $2 == "miss"' "$stats_file" 2>/dev/null | wc -l | tr -d ' ')
    recent_misses=${recent_misses:-0}
    local recent_total=$((recent_hits + recent_misses))
    
    if [ $recent_total -gt 0 ]; then
        local recent_hit_rate=$((recent_hits * 100 / recent_total))
        echo "Last 24 hours:"
        echo "  Requests: $recent_total"
        echo "  Hits: $recent_hits"
        echo "  Misses: $recent_misses"
        echo "  Hit rate: ${recent_hit_rate}%"
    fi
}

#######################################
# Clear cache files based on target pattern.
# Globals:
#   CACHE_DIR - Cache directory path
# Arguments:
#   target - Target pattern (default: "all")
#            Examples: "all", "profile", "profile/service"
# Outputs:
#   Cleanup status messages to stdout
# Returns:
#   0 on success
#######################################
clear_cache() {
    local target="${1:-all}"
    
    case "$target" in
        all)
            echo "Clearing all cache..."
            rm -rf "${CACHE_DIR:?}"/*
            echo "✓ All cache cleared"
            ;;
        */*/*/*)
            # profile/service/region/action 形式
            if [[ -d "$CACHE_DIR/$target" ]]; then
                echo "Clearing cache for: $target"
                rm -rf "${CACHE_DIR:?}/$target"
                echo "✓ Cache cleared for $target"
            else
                echo "No cache found for: $target"
            fi
            ;;
        */*/*)
            # profile/service/region 形式
            if [[ -d "$CACHE_DIR/$target" ]]; then
                echo "Clearing cache for: $target"
                rm -rf "${CACHE_DIR:?}/$target"
                echo "✓ Cache cleared for $target"
            else
                echo "No cache found for: $target"
            fi
            ;;
        */*)
            # profile/service 形式
            if [[ -d "$CACHE_DIR/$target" ]]; then
                echo "Clearing cache for: $target"
                rm -rf "${CACHE_DIR:?}/$target"
                echo "✓ Cache cleared for $target"
            else
                echo "No cache found for: $target"
            fi
            ;;
        *)
            # プロファイル単位またはパターンマッチング
            if [[ -d "$CACHE_DIR/$target" ]]; then
                echo "Clearing cache for profile: $target"
                rm -rf "${CACHE_DIR:?}/$target"
                echo "✓ Cache cleared for profile $target"
            else
                # パターンマッチング（リソースID等）
                echo "Clearing cache matching pattern: $target"
                local count=0
                while IFS= read -r -d '' file; do
                    rm -rf "$file"
                    ((count++))
                done < <(find "$CACHE_DIR" -type f -name "*${target}*" -print0)
                
                if [ $count -eq 0 ]; then
                    echo "No cache found matching: $target"
                else
                    echo "✓ Cleared $count cache files"
                fi
            fi
            ;;
    esac
}

#######################################
# Display cache statistics.
# Globals:
#   CACHE_DIR - Cache directory path
#   CACHE_TTL - Default TTL
# Arguments:
#   target - Optional target path to show stats for
# Outputs:
#   Statistics to stdout
# Returns:
#   0 on success
#######################################
cache_stats() {
    local target="${1:-}"
    
    echo "=== AWS CLI Cache Statistics ==="
    echo "Cache Directory: $CACHE_DIR"
    echo "Default TTL: ${CACHE_TTL}s ($((CACHE_TTL / 60)) minutes)"
    echo ""
    
    if [[ ! -d "$CACHE_DIR" ]] || [ -z "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]; then
        echo "No cache files found"
        return
    fi
    
    # 特定のパスが指定されている場合
    if [[ -n "$target" ]]; then
        if [[ -d "$CACHE_DIR/$target" ]]; then
            echo "Target: $target"
            local target_files=$(find "$CACHE_DIR/$target" -type f -name "*.cache" | wc -l | tr -d ' ')
            local target_size=$(du -sh "$CACHE_DIR/$target" 2>/dev/null | cut -f1)
            echo "Files: $target_files"
            echo "Size: $target_size"
            echo ""
            
            # サブディレクトリ統計
            echo "Subdirectories:"
            for sub_dir in "$CACHE_DIR/$target"/*; do
                if [[ -d "$sub_dir" ]]; then
                    local sub_name=$(basename "$sub_dir")
                    local sub_files=$(find "$sub_dir" -type f -name "*.cache" | wc -l | tr -d ' ')
                    local sub_size=$(du -sh "$sub_dir" 2>/dev/null | cut -f1)
                    echo "  $sub_name: $sub_files files, $sub_size"
                fi
            done
        else
            echo "No cache found for: $target"
        fi
        return
    fi
    
    # 全体統計
    local total_files=$(find "$CACHE_DIR" -type f -name "*.cache" | wc -l | tr -d ' ')
    local total_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    
    echo "Total cache files: $total_files"
    echo "Total cache size: $total_size"
    echo ""
    
    # プロファイル別統計
    echo "By Profile:"
    for profile_dir in "$CACHE_DIR"/*; do
        if [[ -d "$profile_dir" ]]; then
            local profile=$(basename "$profile_dir")
            local profile_files=$(find "$profile_dir" -type f -name "*.cache" | wc -l | tr -d ' ')
            local profile_size=$(du -sh "$profile_dir" 2>/dev/null | cut -f1)
            echo "  $profile: $profile_files files, $profile_size"
            
            # プロファイル内のサービス別統計
            for service_dir in "$profile_dir"/*; do
                if [[ -d "$service_dir" ]]; then
                    local service=$(basename "$service_dir")
                    local service_files=$(find "$service_dir" -type f -name "*.cache" | wc -l | tr -d ' ')
                    local service_size=$(du -sh "$service_dir" 2>/dev/null | cut -f1)
                    echo "    └─ $service: $service_files files, $service_size"
                fi
            done
        fi
    done
    echo ""
    
    # 最近のキャッシュファイル
    echo "Recent cache files:"
    find "$CACHE_DIR" -type f -name "*.cache" -exec ls -lht {} + 2>/dev/null | head -n 10
}

#######################################
# Main function for command-line usage.
# Globals:
#   None
# Arguments:
#   Command and arguments
# Outputs:
#   Command-specific output
# Returns:
#   Command-specific exit code
#######################################
main() {
    case "${1:-}" in
        clear)
            clear_cache "${2:-all}"
            ;;
        clean)
            clean_expired_cache
            ;;
        stats)
            cache_stats "${2:-}"
            ;;
        metrics)
            show_cache_metrics
            ;;
        excludes)
            # キャッシュ除外ルールを表示
            echo "=== Cache Exclude Rules ==="
            echo ""
            echo "Default rules:"
            for rule in "${DEFAULT_EXCLUDE_RULES[@]}"; do
                echo "  $rule"
            done
            echo ""
            if [[ -f "${CACHE_EXCLUDE_CONFIG}" ]]; then
                echo "Custom rules ($CACHE_EXCLUDE_CONFIG):"
                grep -v '^#' "$CACHE_EXCLUDE_CONFIG" | grep -v '^$' | sed 's/^/  /'
            else
                echo "No custom rules file found: $CACHE_EXCLUDE_CONFIG"
                echo "Create this file to add custom exclude rules."
            fi
            echo ""
            echo "Format: service:action"
            echo "Examples:"
            echo "  cloudwatch:get-metric-data    # Exclude specific action"
            echo "  s3:*                          # Exclude all S3 actions"
            echo "  *:list-*                      # Exclude all list actions (not supported yet)"
            ;;
        add-exclude)
            # 除外ルールを追加
            if [[ -z "$2" ]]; then
                echo "Usage: $0 add-exclude <service:action>"
                echo "Example: $0 add-exclude cloudwatch:describe-alarms"
                exit 1
            fi
            
            # 設定ファイルが存在しない場合は作成
            if [[ ! -f "$CACHE_EXCLUDE_CONFIG" ]]; then
                # ディレクトリを作成
                mkdir -p "$(dirname "$CACHE_EXCLUDE_CONFIG")"
                
                cat > "$CACHE_EXCLUDE_CONFIG" << 'EOF'
# AWS CLI Cache Exclude Rules
# Format: service:action
# Examples:
#   cloudwatch:get-metric-data
#   s3:*
#   iam:get-account-authorization-details

EOF
            fi
            
            # ルールを追加
            echo "$2" >> "$CACHE_EXCLUDE_CONFIG"
            echo "✓ Added exclude rule: $2"
            echo "  Config file: $CACHE_EXCLUDE_CONFIG"
            ;;
        remove-exclude)
            # 除外ルールを削除
            if [[ -z "$2" ]]; then
                echo "Usage: $0 remove-exclude <service:action>"
                exit 1
            fi
            
            if [[ ! -f "$CACHE_EXCLUDE_CONFIG" ]]; then
                echo "No custom rules file found: $CACHE_EXCLUDE_CONFIG"
                exit 1
            fi
            
            # ルールを削除（macOS/Linux互換）
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "/^$2$/d" "$CACHE_EXCLUDE_CONFIG"
            else
                sed -i "/^$2$/d" "$CACHE_EXCLUDE_CONFIG"
            fi
            
            echo "✓ Removed exclude rule: $2"
            ;;
        tree)
            # キャッシュディレクトリ構造を表示
            echo "=== Cache Directory Structure ==="
            if command -v tree &> /dev/null; then
                tree -L 4 -h "$CACHE_DIR"
            else
                find "$CACHE_DIR" -type d | head -n 50 | sed "s|$CACHE_DIR|.|g" | sort
            fi
            ;;
        test)
            # テスト実行
            echo "Testing cache functionality..."
            echo ""
            
            echo "1. First call (cache miss):"
            time aws_cached --verbose sts get-caller-identity --output json
            echo ""
            
            echo "2. Second call (cache hit):"
            time aws_cached --verbose sts get-caller-identity --output json
            echo ""
            
            echo "3. Force refresh:"
            time aws_cached --verbose --force-refresh sts get-caller-identity --output json
            ;;
        *)
            echo "AWS CLI Cache Utility"
            echo ""
            echo "Usage:"
            echo "  source scripts/aws_cache.sh              # Load functions"
            echo "  aws_cached [options] <aws-cli-command>   # Execute with cache"
            echo ""
            echo "Commands:"
            echo "  $0 clear [target]           # Clear cache"
            echo "  $0 clean                    # Remove expired cache files"
            echo "  $0 stats [service]          # Show cache statistics"
            echo "  $0 metrics                  # Show cache hit/miss metrics"
            echo "  $0 tree                     # Show cache directory structure"
            echo "  $0 excludes                 # Show cache exclude rules"
            echo "  $0 add-exclude <rule>       # Add exclude rule"
            echo "  $0 remove-exclude <rule>    # Remove exclude rule"
            echo "  $0 test                     # Test cache functionality"
            echo ""
            echo "Clear targets:"
            echo "  all                                    # Clear all cache (default)"
            echo "  my-profile                             # Clear all cache for profile"
            echo "  my-profile/rds                         # Clear RDS cache for profile"
            echo "  my-profile/rds/us-east-1               # Clear RDS cache for region"
            echo "  my-profile/rds/us-east-1/describe-*    # Clear specific action"
            echo "  my-cluster                             # Clear cache matching pattern"
            echo ""
            echo "Options:"
            echo "  --cache-ttl <seconds>  # Override default TTL"
            echo "  --force-refresh        # Ignore cache and refresh"
            echo "  --no-cache             # Bypass cache for this call"
            echo "  --verbose              # Show cache hit/miss info"
            echo ""
            echo "Environment Variables:"
            echo "  AWS_CACHE_DIR              # Cache directory (default: \$XDG_CACHE_HOME/aws-cli)"
            echo "  AWS_CACHE_TTL              # Default TTL in seconds (default: 3600)"
            echo "  AWS_CACHE_MAX_SIZE         # Max cache size in bytes (default: 1073741824 = 1GB)"
            echo "  AWS_CACHE_MAX_FILES        # Max number of cache files (default: 10000)"
            echo "  AWS_CACHE_VERIFY           # Enable integrity check (default: false)"
            echo "  AWS_CACHE_STATS            # Enable statistics recording (default: false)"
            echo "  AWS_CACHE_EXCLUDE_CONFIG   # Exclude rules file (default: \$XDG_CONFIG_HOME/aws-cli/cache-exclude)"
            echo ""
            echo "XDG Base Directory:"
            echo "  XDG_CACHE_HOME             # Base cache directory (default: ~/.cache)"
            echo "  XDG_CONFIG_HOME            # Base config directory (default: ~/.config)"
            echo ""
            echo "AWS CLI Environment Variables (used for cache key):"
            echo "  AWS_PROFILE                # AWS profile (default: default)"
            echo "  AWS_DEFAULT_PROFILE        # Alternative to AWS_PROFILE"
            echo "  AWS_REGION                 # AWS region (default: global)"
            echo "  AWS_DEFAULT_REGION         # Alternative to AWS_REGION"
            echo ""
            echo "Cache Structure:"
            echo "  /tmp/aws_cli_cache/"
            echo "    ├── my-profile/                              # 1. AWS Profile"
            echo "    │   ├── rds/                                 # 2. Service"
            echo "    │   │   ├── us-east-1/                       # 3. Region"
            echo "    │   │   │   ├── describe-db-clusters/        # 4. Action"
            echo "    │   │   │   │   ├── a1b2c3d4e5f6g7h8/        # 5. Params Hash (16 chars, no --query)"
            echo "    │   │   │   │   │   ├── json/                # 6. Output Format"
            echo "    │   │   │   │   │   │   └── hash_3600_1700123456_12345.cache"
            echo "    │   │   │   │   │   └── text/"
            echo "    │   │   │   │   │       └── hash_3600_1700123500_12346.cache"
            echo "    │   │   │   │   └── i9j0k1l2m3n4o5p6/        # Params Hash (16 chars, with --query)"
            echo "    │   │   │   │       └── json/"
            echo "    │   │   │   │           └── hash_300_1700123600_12347.cache"
            echo "    │   │   │   └── describe-db-instances/"
            echo "    │   │   └── ap-northeast-1/"
            echo "    │   └── cloudwatch/"
            echo "    │       └── ap-northeast-1/"
            echo "    │           └── get-metric-statistics/"
            echo "    │               └── m3n4o5p6/                # Params Hash"
            echo "    │                   └── json/"
            echo "    │                       └── hash_300_1700123700_12348.cache"
            echo "    └── another-profile/"
            echo "        └── sts/"
            echo "            └── global/"
            echo "                └── get-caller-identity/"
            echo "                    └── q7r8s9t0/"
            echo "                        └── json/"
            echo "                            └── hash_3600_1700123800_12349.cache"
            echo ""
            echo "Examples:"
            echo "  # Basic usage"
            echo "  aws_cached rds describe-db-clusters --db-cluster-identifier my-cluster"
            echo ""
            echo "  # With custom TTL (5 minutes)"
            echo "  aws_cached --cache-ttl 300 rds describe-db-instances"
            echo ""
            echo "  # Force refresh"
            echo "  aws_cached --force-refresh cloudwatch get-metric-statistics ..."
            echo ""
            echo "  # Clear specific profile"
            echo "  $0 clear my-profile"
            echo ""
            echo "  # Clear specific service in profile"
            echo "  $0 clear my-profile/rds"
            echo ""
            echo "  # Show stats for specific profile"
            echo "  $0 stats my-profile"
            echo ""
            echo "  # Show stats for specific service"
            echo "  $0 stats my-profile/rds"
            echo ""
            echo "  # Show exclude rules"
            echo "  $0 excludes"
            echo ""
            echo "  # Add custom exclude rule"
            echo "  $0 add-exclude cloudwatch:describe-alarms"
            echo ""
            echo "  # Use --no-cache for one-time bypass"
            echo "  aws_cached --no-cache --verbose sts get-caller-identity"
            ;;
    esac
}

# スクリプトとして直接実行された場合のみmainを呼び出す
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi