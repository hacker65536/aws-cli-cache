#!/usr/bin/env bash
#
# AWS CLI Cache - Parameter Extraction Module
# Extracts parameters from AWS CLI commands.
#

# Prevent multiple sourcing
[[ -n "${_AWS_CACHE_EXTRACT_LOADED:-}" ]] && return 0
readonly _AWS_CACHE_EXTRACT_LOADED=1

# Source dependencies for region resolution
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/profile_region.sh"

#######################################
# Extract TTL from cache filename.
# Parses filename format: {hash}_{ttl}_{pid}.cache
# Arguments:
#   $1 - Cache filename (basename only)
# Outputs:
#   TTL value to stdout
# Returns:
#   0 on success, 1 on parse failure
#######################################
extract_ttl_from_filename() {
    local filename="$1"
    
    # Remove .cache extension
    local base="${filename%.cache}"
    
    # Extract last two underscore-separated fields: ttl_pid
    local pid="${base##*_}"
    local without_pid="${base%_*}"
    local ttl="${without_pid##*_}"
    
    # Validate: both should be numeric
    if [[ "$ttl" =~ ^[0-9]+$ ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
        echo "$ttl"
        return 0
    fi
    return 1
}

#######################################
# Extract AWS profile from command arguments.
# Globals:
#   AWS_PROFILE, AWS_DEFAULT_PROFILE
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
        echo "${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-default}}"
    fi
}

#######################################
# Extract service name from AWS CLI command.
# Skips global options to find the service name.
# Arguments:
#   Command line arguments
# Outputs:
#   Service name to stdout
# Returns:
#   0 on success
#######################################
extract_service() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile|--region|--output|--endpoint-url|--no-verify-ssl|--no-paginate|--query|--cli-input-json|--cli-input-yaml|--generate-cli-skeleton)
                shift 2
                ;;
            --*)
                shift
                ;;
            *)
                echo "$1"
                return
                ;;
        esac
    done
}

#######################################
# Extract region from command arguments.
# Uses resolve_region() for full fallback chain:
#   1. --region option
#   2. AWS_REGION env var
#   3. AWS_DEFAULT_REGION env var
#   4. Profile's region from AWS config
#   5. "global" as fallback
# Arguments:
#   Command line arguments
# Outputs:
#   Region name to stdout
# Returns:
#   0 on success
#######################################
extract_region() {
    resolve_region "$@"
}

#######################################
# Extract action from AWS CLI command.
# Arguments:
#   service - Service name
#   ... - Command line arguments
# Outputs:
#   Action name to stdout
# Returns:
#   0 on success
#######################################
extract_action() {
    local service="$1"
    shift
    
    local found_service=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile|--region|--output|--endpoint-url|--no-verify-ssl|--no-paginate|--query|--cli-input-json|--cli-input-yaml|--generate-cli-skeleton)
                shift 2
                ;;
            --*)
                shift
                ;;
            *)
                if [[ "$found_service" == false ]]; then
                    if [[ "$1" == "$service" ]]; then
                        found_service=true
                        shift
                    else
                        shift
                    fi
                else
                    echo "$1"
                    return
                fi
                ;;
        esac
    done
}

#######################################
# Extract output format from command arguments.
# Arguments:
#   Command line arguments
# Outputs:
#   Output format to stdout (default: json)
# Returns:
#   0 on success
#######################################
extract_format() {
    local cmd="$*"
    if echo "$cmd" | grep -q -- "--output"; then
        echo "$cmd" | grep -o -- "--output [^ ]*" | awk '{print $2}'
    else
        echo "json"
    fi
}
