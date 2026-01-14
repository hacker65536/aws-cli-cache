#!/usr/bin/env bash
#
# AWS CLI Cache - Profile Region Resolution Module
# Resolves region from AWS config file based on profile.
#

# Prevent multiple sourcing
[[ -n "${_AWS_CACHE_PROFILE_REGION_LOADED:-}" ]] && return 0
readonly _AWS_CACHE_PROFILE_REGION_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/config.sh"

# In-memory cache for profile-region mappings
declare -gA _PROFILE_REGION_CACHE
declare -g _PROFILE_REGION_CACHE_LOADED=false
declare -g _PROFILE_REGION_CACHE_MTIME=""

#######################################
# Get AWS config file path.
# Globals:
#   AWS_CONFIG_FILE
# Outputs:
#   Config file path to stdout
# Returns:
#   0 on success
#######################################
get_aws_config_file() {
    echo "${AWS_CONFIG_FILE:-$HOME/.aws/config}"
}

#######################################
# Get modification time of a file.
# Arguments:
#   $1 - File path
# Outputs:
#   Modification time (epoch) to stdout
# Returns:
#   0 on success, 1 on failure
#######################################
_get_file_mtime() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f %m "$file" 2>/dev/null
    else
        stat -c %Y "$file" 2>/dev/null
    fi
}

#######################################
# Parse AWS config file and cache profile-region mappings.
# Reads the config file and extracts region settings for each profile.
# Globals:
#   _PROFILE_REGION_CACHE - Associative array for caching
#   _PROFILE_REGION_CACHE_LOADED - Load status flag
#   _PROFILE_REGION_CACHE_MTIME - Config file mtime at load time
# Arguments:
#   None
# Returns:
#   0 on success, 1 if config file not found
#######################################
load_profile_region_cache() {
    local config_file
    config_file=$(get_aws_config_file)
    
    [[ ! -f "$config_file" ]] && return 1
    
    # Check if cache is still valid (file not modified)
    local current_mtime
    current_mtime=$(_get_file_mtime "$config_file")
    
    if [[ "$_PROFILE_REGION_CACHE_LOADED" == true ]] && \
       [[ "$_PROFILE_REGION_CACHE_MTIME" == "$current_mtime" ]]; then
        return 0
    fi
    
    # Clear existing cache
    _PROFILE_REGION_CACHE=()
    
    local current_profile=""
    local line
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Trim whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        
        # Profile section: [profile name] or [default]
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            local section="${BASH_REMATCH[1]}"
            if [[ "$section" == "default" ]]; then
                current_profile="default"
            elif [[ "$section" =~ ^profile[[:space:]]+(.+)$ ]]; then
                current_profile="${BASH_REMATCH[1]}"
            else
                # Not a profile section (e.g., [sso-session])
                current_profile=""
            fi
            continue
        fi
        
        # Region setting within a profile section
        if [[ -n "$current_profile" ]] && [[ "$line" =~ ^region[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            local region="${BASH_REMATCH[1]}"
            # Trim whitespace from region value
            region="${region#"${region%%[![:space:]]*}"}"
            region="${region%"${region##*[![:space:]]}"}"
            _PROFILE_REGION_CACHE["$current_profile"]="$region"
        fi
    done < "$config_file"
    
    _PROFILE_REGION_CACHE_LOADED=true
    _PROFILE_REGION_CACHE_MTIME="$current_mtime"
    
    return 0
}

#######################################
# Get region for a specific profile from cache.
# Uses lazy loading with optimized search for large config files.
# Globals:
#   _PROFILE_REGION_CACHE
# Arguments:
#   $1 - Profile name
# Outputs:
#   Region name to stdout (empty if not found)
# Returns:
#   0 if found, 1 if not found
#######################################
get_profile_region() {
    local profile="$1"
    
    # Check if already cached
    if [[ -n "${_PROFILE_REGION_CACHE[$profile]:-}" ]]; then
        echo "${_PROFILE_REGION_CACHE[$profile]}"
        return 0
    fi
    
    # Lazy load: search for specific profile only
    local config_file
    config_file=$(get_aws_config_file)
    [[ ! -f "$config_file" ]] && return 1
    
    # Use awk for fast profile-specific search
    # Escape special characters in profile name for regex
    local escaped_profile="${profile//\\/\\\\}"
    escaped_profile="${escaped_profile//\[/\\[}"
    escaped_profile="${escaped_profile//\]/\\]}"
    escaped_profile="${escaped_profile//\./\\.}"
    escaped_profile="${escaped_profile//\*/\\*}"
    escaped_profile="${escaped_profile//\^/\\^}"
    escaped_profile="${escaped_profile//\$/\\$}"
    
    local found_region
    if [[ "$profile" == "default" ]]; then
        found_region=$(awk '
            /^\[default\]/ { in_section=1; next }
            /^\[/ { in_section=0 }
            in_section && /^[[:space:]]*region[[:space:]]*=/ {
                sub(/^[[:space:]]*region[[:space:]]*=[[:space:]]*/, "")
                sub(/[[:space:]]*$/, "")
                print
                exit
            }
        ' "$config_file")
    else
        found_region=$(awk -v prof="$escaped_profile" '
            BEGIN { pattern = "^\\[profile[[:space:]]+" prof "\\]$" }
            $0 ~ pattern { in_section=1; next }
            /^\[/ { in_section=0 }
            in_section && /^[[:space:]]*region[[:space:]]*=/ {
                sub(/^[[:space:]]*region[[:space:]]*=[[:space:]]*/, "")
                sub(/[[:space:]]*$/, "")
                print
                exit
            }
        ' "$config_file")
    fi
    
    if [[ -n "$found_region" ]]; then
        # Cache it
        _PROFILE_REGION_CACHE["$profile"]="$found_region"
        echo "$found_region"
        return 0
    fi
    
    return 1
}

#######################################
# Resolve region with full fallback chain.
# Priority:
#   1. --region command option
#   2. AWS_REGION environment variable
#   3. AWS_DEFAULT_REGION environment variable
#   4. Profile's region from AWS config file
# Arguments:
#   $@ - Command line arguments (to extract --region and --profile)
# Outputs:
#   Resolved region to stdout (empty if not resolved)
# Returns:
#   0 on success, 1 if region cannot be resolved
#######################################
resolve_region() {
    local cmd="$*"
    
    # 1. Check --region option
    if echo "$cmd" | grep -q -- "--region"; then
        echo "$cmd" | grep -o -- "--region [^ ]*" | awk '{print $2}'
        return 0
    fi
    
    # 2. Check AWS_REGION environment variable
    if [[ -n "${AWS_REGION:-}" ]]; then
        echo "$AWS_REGION"
        return 0
    fi
    
    # 3. Check AWS_DEFAULT_REGION environment variable
    if [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then
        echo "$AWS_DEFAULT_REGION"
        return 0
    fi
    
    # 4. Get profile and look up its region
    local profile
    if echo "$cmd" | grep -q -- "--profile"; then
        profile=$(echo "$cmd" | grep -o -- "--profile [^ ]*" | awk '{print $2}')
    else
        profile="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-default}}"
    fi
    
    local profile_region
    if profile_region=$(get_profile_region "$profile"); then
        echo "$profile_region"
        return 0
    fi
    
    # Region could not be resolved
    return 1
}

#######################################
# Clear the profile-region cache.
# Useful for testing or when config file changes.
# Globals:
#   _PROFILE_REGION_CACHE
#   _PROFILE_REGION_CACHE_LOADED
#   _PROFILE_REGION_CACHE_MTIME
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
clear_profile_region_cache() {
    _PROFILE_REGION_CACHE=()
    _PROFILE_REGION_CACHE_LOADED=false
    _PROFILE_REGION_CACHE_MTIME=""
}

#######################################
# Debug: Show all cached profile-region mappings.
# Globals:
#   _PROFILE_REGION_CACHE
# Outputs:
#   Profile-region mappings to stdout
# Returns:
#   0 on success
#######################################
debug_profile_region_cache() {
    load_profile_region_cache
    
    echo "Profile-Region Cache:"
    for profile in "${!_PROFILE_REGION_CACHE[@]}"; do
        echo "  $profile -> ${_PROFILE_REGION_CACHE[$profile]}"
    done
}
