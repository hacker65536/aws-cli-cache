#!/usr/bin/env bash
#
# AWS CLI Cache Layer
# Version: 4.0.0
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

# Determine library directory
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="${_SCRIPT_DIR}/lib"

# Source all modules
source "${_LIB_DIR}/config.sh"
source "${_LIB_DIR}/excludes.sh"
source "${_LIB_DIR}/extract.sh"
source "${_LIB_DIR}/hash.sh"
source "${_LIB_DIR}/limits.sh"
source "${_LIB_DIR}/cache_io.sh"
source "${_LIB_DIR}/stats.sh"
source "${_LIB_DIR}/core.sh"
source "${_LIB_DIR}/cli.sh"

# Ensure cache directory exists (only when sourced, not during tests)
if [[ "${AWS_CACHE_SKIP_INIT:-}" != true ]]; then
    ensure_cache_dir
fi

#######################################
# Main function for command-line usage.
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
            show_excludes
            ;;
        add-exclude)
            add_exclude "$2"
            ;;
        remove-exclude)
            remove_exclude "$2"
            ;;
        tree)
            show_tree
            ;;
        test)
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
            show_help "$0"
            ;;
    esac
}

# Run main only when executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
