#!/usr/bin/env bash
#
# AWS CLI Cache - Configuration Module
# Handles environment variables and default settings.
#

# Prevent multiple sourcing
[[ -n "${_AWS_CACHE_CONFIG_LOADED:-}" ]] && return 0
readonly _AWS_CACHE_CONFIG_LOADED=1

#######################################
# Initialize configuration variables.
# Sets up XDG directories and cache settings.
# Globals:
#   XDG_CACHE_HOME, XDG_CONFIG_HOME
#   CACHE_DIR, CACHE_TTL, CACHE_MAX_SIZE, CACHE_MAX_FILES
#   CACHE_EXCLUDE_CONFIG
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
init_config() {
    # XDG Base Directory仕様に従ったディレクトリ
    XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    
    # キャッシュ設定
    CACHE_DIR="${AWS_CACHE_DIR:-$XDG_CACHE_HOME/aws-cli}"
    CACHE_TTL="${AWS_CACHE_TTL:-3600}"  # デフォルト1時間
    CACHE_MAX_SIZE="${AWS_CACHE_MAX_SIZE:-1073741824}"  # デフォルト1GB
    CACHE_MAX_FILES="${AWS_CACHE_MAX_FILES:-10000}"     # デフォルト10,000ファイル
    
    # 除外設定ファイル
    CACHE_EXCLUDE_CONFIG="${AWS_CACHE_EXCLUDE_CONFIG:-$XDG_CONFIG_HOME/aws-cli/cache-exclude}"
}

#######################################
# Ensure cache directory exists.
# Creates the directory if it doesn't exist.
# Globals:
#   CACHE_DIR
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
ensure_cache_dir() {
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
}

# Initialize on source (can be called again to reinitialize)
init_config
