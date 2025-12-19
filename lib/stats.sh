#!/usr/bin/env bash
#
# AWS CLI Cache - Statistics Module
# Handles cache hit/miss statistics recording and display.
#

# Prevent multiple sourcing
[[ -n "${_AWS_CACHE_STATS_LOADED:-}" ]] && return 0
readonly _AWS_CACHE_STATS_LOADED=1

#######################################
# Record cache hit.
# Runs asynchronously in background.
# Globals:
#   AWS_CACHE_STATS, CACHE_DIR
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
record_cache_hit() {
    [[ "${AWS_CACHE_STATS:-false}" != true ]] && return 0
    
    local stats_file="$CACHE_DIR/.stats"
    local timestamp=$(date +%s)
    (echo "$timestamp,hit" >> "$stats_file" 2>/dev/null) &
}

#######################################
# Record cache miss.
# Runs asynchronously in background.
# Globals:
#   AWS_CACHE_STATS, CACHE_DIR
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
record_cache_miss() {
    [[ "${AWS_CACHE_STATS:-false}" != true ]] && return 0
    
    local stats_file="$CACHE_DIR/.stats"
    local timestamp=$(date +%s)
    (echo "$timestamp,miss" >> "$stats_file" 2>/dev/null) &
}

#######################################
# Display cache hit/miss metrics.
# Globals:
#   CACHE_DIR
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
# Display cache statistics.
# Globals:
#   CACHE_DIR, CACHE_TTL
# Arguments:
#   target - Optional target path
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
    
    if [[ -n "$target" ]]; then
        if [[ -d "$CACHE_DIR/$target" ]]; then
            echo "Target: $target"
            local target_files=$(find "$CACHE_DIR/$target" -type f -name "*.cache" | wc -l | tr -d ' ')
            local target_size=$(du -sh "$CACHE_DIR/$target" 2>/dev/null | cut -f1)
            echo "Files: $target_files"
            echo "Size: $target_size"
            echo ""
            
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
    
    local total_files=$(find "$CACHE_DIR" -type f -name "*.cache" | wc -l | tr -d ' ')
    local total_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    
    echo "Total cache files: $total_files"
    echo "Total cache size: $total_size"
    echo ""
    
    echo "By Profile:"
    for profile_dir in "$CACHE_DIR"/*; do
        if [[ -d "$profile_dir" ]]; then
            local profile=$(basename "$profile_dir")
            local profile_files=$(find "$profile_dir" -type f -name "*.cache" | wc -l | tr -d ' ')
            local profile_size=$(du -sh "$profile_dir" 2>/dev/null | cut -f1)
            echo "  $profile: $profile_files files, $profile_size"
            
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
    
    echo "Recent cache files:"
    find "$CACHE_DIR" -type f -name "*.cache" -exec ls -lht {} + 2>/dev/null | head -n 10
}
