#!/usr/bin/env bash
#
# AWS CLI Cache - Cache Limits Module
# Handles LRU eviction and size limits.
#

# Prevent multiple sourcing
[[ -n "${_AWS_CACHE_LIMITS_LOADED:-}" ]] && return 0
readonly _AWS_CACHE_LIMITS_LOADED=1

#######################################
# Check and enforce cache size limits using LRU eviction.
# Uses probabilistic checking (1% chance) for performance.
# Globals:
#   CACHE_DIR, CACHE_MAX_FILES, CACHE_MAX_SIZE
# Arguments:
#   force - Set to "force" to bypass probabilistic check
# Returns:
#   0 on success
#######################################
check_cache_limits() {
    local force="${1:-}"
    
    # 確率的チェック: 1%の確率でのみ実行（パフォーマンス最適化）
    if [[ "$force" != "force" ]]; then
        [[ $((RANDOM % 100)) -ne 0 ]] && return 0
    fi
    
    # ファイル数チェック
    local file_count
    file_count=$(find "$CACHE_DIR" -type f -name "*.cache" 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$file_count" -ge "$CACHE_MAX_FILES" ]; then
        local files_to_delete=$((file_count - CACHE_MAX_FILES + 100))
        
        find "$CACHE_DIR" -type f -name "*.cache" 2>/dev/null | \
            xargs ls -tu 2>/dev/null | \
            tail -n "$files_to_delete" | \
            while IFS= read -r file; do
                [ -f "$file" ] && rm -f "$file" 2>/dev/null
            done
    fi
    
    # ディスク使用量チェック
    local cache_size
    cache_size=$(du -sk "$CACHE_DIR" 2>/dev/null | cut -f1)
    local max_size_kb=$((CACHE_MAX_SIZE / 1024))
    
    if [[ -n "$cache_size" ]] && [ "$cache_size" -ge "$max_size_kb" ]; then
        local target_size_kb=$((max_size_kb * 80 / 100))
        
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
# Clean expired cache files.
# Globals:
#   CACHE_DIR
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
    
    # Source extract module for TTL extraction
    local lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${lib_dir}/extract.sh"
    
    while IFS= read -r -d '' cache_file; do
        local filename
        filename=$(basename "$cache_file")
        
        local file_ttl
        if file_ttl=$(extract_ttl_from_filename "$filename"); then
            local file_mtime
            if [[ "$OSTYPE" == "darwin"* ]]; then
                file_mtime=$(stat -f %m "$cache_file" 2>/dev/null)
            else
                file_mtime=$(stat -c %Y "$cache_file" 2>/dev/null)
            fi
            
            if [[ -n "$file_mtime" ]]; then
                local expiry_time=$((file_mtime + file_ttl))
                
                if [[ ${expiry_time} -le ${current_time} ]]; then
                    local file_size
                    file_size=$(du -k "$cache_file" | cut -f1)
                    rm -f "$cache_file"
                    ((count++))
                    ((freed_size+=file_size))
                fi
            fi
        fi
    done < <(find "$CACHE_DIR" -type f -name "*.cache" -print0)
    
    echo "Removed ${count} expired cache files"
    echo "Freed space: ${freed_size}KB"
    
    find "$CACHE_DIR" -type d -empty -delete 2>/dev/null
}
