#!/usr/bin/env bash
#
# AWS CLI Cache - Hash Generation Module
# Generates cache keys and parameter hashes.
#

# Prevent multiple sourcing
[[ -n "${_AWS_CACHE_HASH_LOADED:-}" ]] && return 0
readonly _AWS_CACHE_HASH_LOADED=1

#######################################
# Generate parameter hash.
# Excludes --region, --profile, --output from hash.
# Arguments:
#   Command line arguments
# Outputs:
#   16-character hash to stdout
# Returns:
#   0 on success
#######################################
generate_params_hash() {
    local cmd="$*"
    
    # sedを使用して確実にオプションと値を除外
    local params
    params=$(echo "$cmd" | sed -E 's/--region[[:space:]]+[^[:space:]]+//g; s/--profile[[:space:]]+[^[:space:]]+//g; s/--output[[:space:]]+[^[:space:]]+//g')
    # 余分な空白を削除
    params=$(echo "$params" | tr -s ' ' | sed 's/^ //; s/ $//')
    
    # ハッシュ化（短縮版: 最初の16文字）
    local hash
    hash=$(echo -n "$params" | shasum -a 256 | cut -c1-16)
    echo "${hash//[^a-zA-Z0-9]/_}"
}

#######################################
# Generate cache key from full command.
# Excludes --region, --profile, --output from hash.
# Arguments:
#   Command line arguments
# Outputs:
#   64-character SHA256 hash to stdout
# Returns:
#   0 on success
#######################################
generate_cache_key() {
    local cmd="$*"
    
    # sedを使用して確実にオプションと値を除外
    local params
    params=$(echo "$cmd" | sed -E 's/--region[[:space:]]+[^[:space:]]+//g; s/--profile[[:space:]]+[^[:space:]]+//g; s/--output[[:space:]]+[^[:space:]]+//g')
    # 余分な空白を削除
    params=$(echo "$params" | tr -s ' ' | sed 's/^ //; s/ $//')
    
    local hash
    hash=$(echo -n "$params" | shasum -a 256)
    echo "${hash%% *}"
}
