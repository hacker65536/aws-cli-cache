#!/usr/bin/env bash
#
# AWS CLI Cache - Cache I/O Module
# Handles reading and writing cache files.
#

# Prevent multiple sourcing
[[ -n "${_AWS_CACHE_IO_LOADED:-}" ]] && return 0
readonly _AWS_CACHE_IO_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/config.sh"
source "${_LIB_DIR}/extract.sh"
source "${_LIB_DIR}/hash.sh"
source "${_LIB_DIR}/limits.sh"

#######################################
# Get cache file path for a command.
# Creates directory structure if needed.
# Globals:
#   CACHE_DIR, CACHE_TTL
# Arguments:
#   ttl - TTL value
#   ... - AWS CLI command arguments
# Outputs:
#   Cache file path to stdout
# Returns:
#   0 on success
#######################################
get_cache_file() {
    local ttl="${1:-$CACHE_TTL}"
    shift
    
    local profile=$(extract_profile "$@")
    local service=$(extract_service "$@")
    local region=$(extract_region "$@")
    local action=$(extract_action "$service" "$@")
    local params_hash=$(generate_params_hash "$@")
    local output_format=$(extract_format "$@")
    local cache_key=$(generate_cache_key "$@")
    
    # ディレクトリ構造: profile/service/region/action/params_hash/output_format/
    local cache_path="$CACHE_DIR/$profile"
    [[ -n "${service}" ]] && cache_path="$cache_path/$service"
    [[ -n "${region}" ]] && cache_path="$cache_path/$region"
    [[ -n "${action}" ]] && cache_path="$cache_path/$action"
    cache_path="$cache_path/$params_hash"
    cache_path="$cache_path/$output_format"
    
    mkdir -p "$cache_path" 2>/dev/null || true
    
    echo "$cache_path/${cache_key}_${ttl}_$$.cache"
}

#######################################
# Find valid cache file for a command.
# Globals:
#   CACHE_DIR, CACHE_TTL
# Arguments:
#   ttl - TTL value
#   ... - AWS CLI command arguments
# Outputs:
#   Cache file path to stdout if found
# Returns:
#   0 if found, 1 if not found
#######################################
find_valid_cache_file() {
    local ttl="${1:-$CACHE_TTL}"
    shift
    
    local profile=$(extract_profile "$@")
    local service=$(extract_service "$@")
    local region=$(extract_region "$@")
    local action=$(extract_action "$service" "$@")
    local params_hash=$(generate_params_hash "$@")
    local output_format=$(extract_format "$@")
    local cache_key=$(generate_cache_key "$@")
    
    local cache_path="$CACHE_DIR/$profile/$service/$region/$action/$params_hash/$output_format"
    
    [[ ! -d "${cache_path}" ]] && return 1
    
    local current_time=$(date +%s)
    local latest_file
    latest_file=$(ls -t "$cache_path/${cache_key}_"*.cache 2>/dev/null | head -n 1)
    
    [[ -z "$latest_file" ]] || [[ ! -f "$latest_file" ]] && return 1
    
    local filename=$(basename "$latest_file")
    local file_ttl
    file_ttl=$(extract_ttl_from_filename "$filename") || return 1
    
    local file_mtime
    if [[ "$OSTYPE" == "darwin"* ]]; then
        file_mtime=$(stat -f %m "$latest_file" 2>/dev/null)
    else
        file_mtime=$(stat -c %Y "$latest_file" 2>/dev/null)
    fi
    
    [[ -z "$file_mtime" ]] && return 1
    
    local expiry_time=$((file_mtime + file_ttl))
    
    if [[ ${expiry_time} -gt ${current_time} ]]; then
        echo "$latest_file"
        return 0
    fi
    
    return 1
}

#######################################
# Check if cache file is valid.
# Arguments:
#   cache_file - Path to cache file
# Returns:
#   0 if valid, 1 if invalid or expired
#######################################
is_cache_valid() {
    local cache_file="$1"
    
    [[ ! -f "${cache_file}" ]] && return 1
    
    local filename=$(basename "$cache_file")
    local file_ttl
    file_ttl=$(extract_ttl_from_filename "$filename") || return 1
    
    local file_mtime
    if [[ "$OSTYPE" == "darwin"* ]]; then
        file_mtime=$(stat -f %m "$cache_file" 2>/dev/null)
    else
        file_mtime=$(stat -c %Y "$cache_file" 2>/dev/null)
    fi
    
    [[ -z "$file_mtime" ]] && return 1
    
    local current_time=$(date +%s)
    local expiry_time=$((file_mtime + file_ttl))
    
    [[ ${expiry_time} -gt ${current_time} ]]
}

#######################################
# Read data from cache file.
# Arguments:
#   cache_file - Path to cache file
#   verify - Enable integrity check (optional)
# Outputs:
#   Cache content to stdout
# Returns:
#   0 on success, 1 on failure
#######################################
read_cache() {
    local cache_file="$1"
    local verify="${2:-false}"
    
    if [[ "${verify}" == true ]] && [[ -f "${cache_file}.sha256" ]]; then
        local stored_hash
        stored_hash=$(cat "${cache_file}.sha256" 2>/dev/null)
        local actual_hash
        actual_hash=$(shasum -a 256 "$cache_file" 2>/dev/null | cut -d' ' -f1)
        
        if [[ "${stored_hash}" != "${actual_hash}" ]]; then
            rm -f "$cache_file" "${cache_file}.sha256" 2>/dev/null
            return 1
        fi
    fi
    
    cat "$cache_file"
}

#######################################
# Write data to cache file atomically.
# Globals:
#   AWS_CACHE_VERIFY
# Arguments:
#   cache_file - Path to cache file
#   data - Data to write
# Returns:
#   0 on success, 1 on failure
#######################################
write_cache() {
    local cache_file="$1"
    local data="$2"
    local temp_file="${cache_file}.tmp.$$"
    
    check_cache_limits
    
    echo "$data" > "$temp_file"
    
    if [[ "${AWS_CACHE_VERIFY:-false}" == true ]]; then
        shasum -a 256 "$temp_file" 2>/dev/null | cut -d' ' -f1 > "${temp_file}.sha256"
    fi
    
    mv -f "$temp_file" "$cache_file" 2>/dev/null || {
        rm -f "$temp_file" "${temp_file}.sha256"
        return 1
    }
    
    if [[ -f "${temp_file}.sha256" ]]; then
        mv -f "${temp_file}.sha256" "${cache_file}.sha256" 2>/dev/null
    fi
}
