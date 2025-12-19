#!/usr/bin/env bash
#
# AWS CLI Cache - Core Module
# Main caching function for AWS CLI commands.
#

# Prevent multiple sourcing
[[ -n "${_AWS_CACHE_CORE_LOADED:-}" ]] && return 0
readonly _AWS_CACHE_CORE_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/config.sh"
source "${_LIB_DIR}/excludes.sh"
source "${_LIB_DIR}/extract.sh"
source "${_LIB_DIR}/cache_io.sh"
source "${_LIB_DIR}/stats.sh"

#######################################
# Execute AWS CLI command with caching support.
# Globals:
#   CACHE_TTL, CACHE_DIR, AWS_CACHE_VERIFY, AWS_CACHE_STATS
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
    
    # --no-cache オプションの場合
    if [[ "$no_cache" == true ]]; then
        [ "$verbose" = true ] && echo "[CACHE] Bypass: Executing AWS CLI without cache" >&2
        aws "$@"
        return $?
    fi
    
    # キャッシュ対象かチェック
    if ! is_cacheable "$service" "$action"; then
        [ "$verbose" = true ] && echo "[CACHE] Excluded: $service:$action (not cacheable)" >&2
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
        if [[ "$verbose" == true ]]; then
            echo "[CACHE] Hit: $cache_file" >&2
            local filename=$(basename "$cache_file")
            local file_ttl
            if file_ttl=$(extract_ttl_from_filename "$filename"); then
                local file_mtime
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    file_mtime=$(stat -f %m "$cache_file" 2>/dev/null)
                else
                    file_mtime=$(stat -c %Y "$cache_file" 2>/dev/null)
                fi
                local current_time=$(date +%s)
                local age=$((current_time - file_mtime))
                local remaining=$((file_ttl - age))
                echo "[CACHE] Age: ${age}s, Remaining: ${remaining}s, TTL: ${file_ttl}s" >&2
            fi
        fi
        
        record_cache_hit
        read_cache "$cache_file" "${AWS_CACHE_VERIFY:-false}"
        return 0
    fi
    
    # キャッシュミス - AWS CLI実行
    [ "$verbose" = true ] && echo "[CACHE] Miss: Executing AWS CLI" >&2
    
    local temp_stdout=$(mktemp)
    local temp_stderr=$(mktemp)
    
    aws "$@" > "$temp_stdout" 2> "$temp_stderr"
    local exit_code=$?
    
    local result
    result=$(cat "$temp_stdout")
    local error_output
    error_output=$(cat "$temp_stderr")
    
    rm -f "$temp_stdout" "$temp_stderr"
    
    if [ $exit_code -eq 0 ]; then
        record_cache_miss
        
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
        [ -n "$error_output" ] && echo "$error_output" >&2
        return $exit_code
    fi
}
