#!/usr/bin/env bash
#
# AWS CLI Cache - CLI Module
# Handles command-line interface and management commands.
#

# Prevent multiple sourcing
[[ -n "${_AWS_CACHE_CLI_LOADED:-}" ]] && return 0
readonly _AWS_CACHE_CLI_LOADED=1

#######################################
# Clear cache files based on target pattern.
# Globals:
#   CACHE_DIR
# Arguments:
#   target - Target pattern (default: "all")
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
            if [[ -d "$CACHE_DIR/$target" ]]; then
                echo "Clearing cache for: $target"
                rm -rf "${CACHE_DIR:?}/$target"
                echo "✓ Cache cleared for $target"
            else
                echo "No cache found for: $target"
            fi
            ;;
        */*/*)
            if [[ -d "$CACHE_DIR/$target" ]]; then
                echo "Clearing cache for: $target"
                rm -rf "${CACHE_DIR:?}/$target"
                echo "✓ Cache cleared for $target"
            else
                echo "No cache found for: $target"
            fi
            ;;
        */*)
            if [[ -d "$CACHE_DIR/$target" ]]; then
                echo "Clearing cache for: $target"
                rm -rf "${CACHE_DIR:?}/$target"
                echo "✓ Cache cleared for $target"
            else
                echo "No cache found for: $target"
            fi
            ;;
        *)
            if [[ -d "$CACHE_DIR/$target" ]]; then
                echo "Clearing cache for profile: $target"
                rm -rf "${CACHE_DIR:?}/$target"
                echo "✓ Cache cleared for profile $target"
            else
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
# Show exclude rules.
# Globals:
#   DEFAULT_EXCLUDE_RULES, CACHE_EXCLUDE_CONFIG
# Arguments:
#   None
# Outputs:
#   Exclude rules to stdout
# Returns:
#   0 on success
#######################################
show_excludes() {
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
}

#######################################
# Add exclude rule.
# Globals:
#   CACHE_EXCLUDE_CONFIG
# Arguments:
#   rule - Rule to add (service:action format)
# Returns:
#   0 on success, 1 on failure
#######################################
add_exclude() {
    local rule="$1"
    
    if [[ -z "$rule" ]]; then
        echo "Usage: add-exclude <service:action>"
        echo "Example: add-exclude cloudwatch:describe-alarms"
        return 1
    fi
    
    if [[ ! -f "$CACHE_EXCLUDE_CONFIG" ]]; then
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
    
    echo "$rule" >> "$CACHE_EXCLUDE_CONFIG"
    echo "✓ Added exclude rule: $rule"
    echo "  Config file: $CACHE_EXCLUDE_CONFIG"
}

#######################################
# Remove exclude rule.
# Globals:
#   CACHE_EXCLUDE_CONFIG
# Arguments:
#   rule - Rule to remove
# Returns:
#   0 on success, 1 on failure
#######################################
remove_exclude() {
    local rule="$1"
    
    if [[ -z "$rule" ]]; then
        echo "Usage: remove-exclude <service:action>"
        return 1
    fi
    
    if [[ ! -f "$CACHE_EXCLUDE_CONFIG" ]]; then
        echo "No custom rules file found: $CACHE_EXCLUDE_CONFIG"
        return 1
    fi
    
    # macOS/Linux互換の削除
    local temp_file="${CACHE_EXCLUDE_CONFIG}.tmp"
    grep -v "^${rule}$" "$CACHE_EXCLUDE_CONFIG" > "$temp_file"
    mv "$temp_file" "$CACHE_EXCLUDE_CONFIG"
    
    echo "✓ Removed exclude rule: $rule"
}

#######################################
# Show cache directory tree.
# Globals:
#   CACHE_DIR
# Arguments:
#   None
# Outputs:
#   Directory structure to stdout
# Returns:
#   0 on success
#######################################
show_tree() {
    echo "=== Cache Directory Structure ==="
    if command -v tree &> /dev/null; then
        tree -L 4 -h "$CACHE_DIR"
    else
        find "$CACHE_DIR" -type d | head -n 50 | sed "s|$CACHE_DIR|.|g" | sort
    fi
}

#######################################
# Show usage help.
# Arguments:
#   script_name - Name of the script
# Outputs:
#   Help text to stdout
# Returns:
#   0 on success
#######################################
show_help() {
    local script_name="${1:-aws_cache.sh}"
    
    cat << EOF
AWS CLI Cache Utility

Usage:
  source ${script_name}                    # Load functions
  aws_cached [options] <aws-cli-command>   # Execute with cache

Commands:
  ${script_name} clear [target]           # Clear cache
  ${script_name} clean                    # Remove expired cache files
  ${script_name} stats [service]          # Show cache statistics
  ${script_name} metrics                  # Show cache hit/miss metrics
  ${script_name} tree                     # Show cache directory structure
  ${script_name} excludes                 # Show cache exclude rules
  ${script_name} add-exclude <rule>       # Add exclude rule
  ${script_name} remove-exclude <rule>    # Remove exclude rule
  ${script_name} test                     # Test cache functionality

Options:
  --cache-ttl <seconds>  # Override default TTL
  --force-refresh        # Ignore cache and refresh
  --no-cache             # Bypass cache for this call
  --verbose              # Show cache hit/miss info

Environment Variables:
  AWS_CACHE_DIR              # Cache directory (default: \$XDG_CACHE_HOME/aws-cli)
  AWS_CACHE_TTL              # Default TTL in seconds (default: 3600)
  AWS_CACHE_MAX_SIZE         # Max cache size in bytes (default: 1073741824 = 1GB)
  AWS_CACHE_MAX_FILES        # Max number of cache files (default: 10000)
  AWS_CACHE_VERIFY           # Enable integrity check (default: false)
  AWS_CACHE_STATS            # Enable statistics recording (default: false)
  AWS_CACHE_EXCLUDE_CONFIG   # Exclude rules file

Examples:
  # Basic usage
  aws_cached rds describe-db-clusters --db-cluster-identifier my-cluster

  # With custom TTL (5 minutes)
  aws_cached --cache-ttl 300 rds describe-db-instances

  # Force refresh
  aws_cached --force-refresh cloudwatch get-metric-statistics ...

  # Clear specific profile
  ${script_name} clear my-profile
EOF
}
