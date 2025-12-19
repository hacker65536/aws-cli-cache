#!/usr/bin/env bash
#
# AWS CLI Cache - Exclude Rules Module
# Handles cache exclusion rules for write operations.
#

# キャッシュ除外ルールのキャッシュ（パフォーマンス最適化）
# テスト時にリセット可能にするため、readonly ガードの外に配置
if [[ -z "${CACHED_EXCLUDE_RULES+x}" ]]; then
    declare -a CACHED_EXCLUDE_RULES=()
fi
IS_EXCLUDES_LOADED="${IS_EXCLUDES_LOADED:-false}"

# デフォルト除外ルール
# 形式: "service:action" または "service:*" または "*:action"
# Note: declare -p で配列の存在を確認（set -u 環境でも安全）
# Note: declare -g を使用して、関数内からsourceされてもグローバルスコープで定義
if ! declare -p DEFAULT_EXCLUDE_RULES &>/dev/null; then
declare -g -a DEFAULT_EXCLUDE_RULES=(
    # RDS
    "rds:create-db-cluster"
    "rds:create-db-instance"
    "rds:modify-db-cluster"
    "rds:modify-db-instance"
    "rds:delete-db-cluster"
    "rds:delete-db-instance"
    "rds:reboot-db-instance"
    "rds:start-db-cluster"
    "rds:stop-db-cluster"
    
    # EC2
    "ec2:run-instances"
    "ec2:start-instances"
    "ec2:stop-instances"
    "ec2:terminate-instances"
    "ec2:reboot-instances"
    "ec2:create-volume"
    "ec2:delete-volume"
    "ec2:attach-volume"
    "ec2:detach-volume"
    
    # S3
    "s3:put-object"
    "s3:delete-object"
    "s3:create-bucket"
    "s3:delete-bucket"
    "s3:put-bucket-policy"
    "s3:delete-bucket-policy"
    
    # Lambda
    "lambda:create-function"
    "lambda:update-function-code"
    "lambda:update-function-configuration"
    "lambda:delete-function"
    "lambda:invoke"
    "lambda:publish-version"
    
    # DynamoDB
    "dynamodb:create-table"
    "dynamodb:update-table"
    "dynamodb:delete-table"
    "dynamodb:put-item"
    "dynamodb:update-item"
    "dynamodb:delete-item"
    "dynamodb:batch-write-item"
    
    # IAM
    "iam:create-user"
    "iam:delete-user"
    "iam:create-role"
    "iam:delete-role"
    "iam:attach-role-policy"
    "iam:detach-role-policy"
    "iam:put-user-policy"
    "iam:delete-user-policy"
    
    # CloudFormation
    "cloudformation:create-stack"
    "cloudformation:update-stack"
    "cloudformation:delete-stack"
    
    # ECS
    "ecs:create-cluster"
    "ecs:delete-cluster"
    "ecs:create-service"
    "ecs:update-service"
    "ecs:delete-service"
    "ecs:run-task"
    "ecs:stop-task"
    
    # SQS
    "sqs:send-message"
    "sqs:send-message-batch"
    "sqs:delete-message"
    "sqs:delete-message-batch"
    "sqs:purge-queue"
    
    # SNS
    "sns:publish"
    "sns:create-topic"
    "sns:delete-topic"
    "sns:subscribe"
    "sns:unsubscribe"
    
    # Athena
    "athena:start-query-execution"
    "athena:stop-query-execution"
    "athena:create-named-query"
    "athena:delete-named-query"
    "athena:create-work-group"
    "athena:delete-work-group"
    "athena:update-work-group"
)
fi

#######################################
# Reset exclude rules cache.
# Forces reload on next access.
# Globals:
#   IS_EXCLUDES_LOADED, CACHED_EXCLUDE_RULES
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
reset_excludes_cache() {
    IS_EXCLUDES_LOADED=false
    CACHED_EXCLUDE_RULES=()
}

#######################################
# Load cache exclude rules from config file.
# Globals:
#   IS_EXCLUDES_LOADED, CACHED_EXCLUDE_RULES
#   DEFAULT_EXCLUDE_RULES, CACHE_EXCLUDE_CONFIG
# Arguments:
#   None
# Outputs:
#   Exclude rules to stdout (one per line)
# Returns:
#   0 on success
#######################################
load_cache_excludes() {
    # 既に読み込み済みの場合はキャッシュを返す
    if [[ "${IS_EXCLUDES_LOADED}" == true ]]; then
        printf '%s\n' "${CACHED_EXCLUDE_RULES[@]}"
        return
    fi
    
    local -a excludes=("${DEFAULT_EXCLUDE_RULES[@]}")
    
    # 設定ファイルが存在する場合は読み込み
    if [[ -f "${CACHE_EXCLUDE_CONFIG}" ]]; then
        while IFS= read -r line; do
            # コメント行と空行をスキップ
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue
            excludes+=("$line")
        done < "$CACHE_EXCLUDE_CONFIG"
    fi
    
    # キャッシュに保存
    CACHED_EXCLUDE_RULES=("${excludes[@]}")
    IS_EXCLUDES_LOADED=true
    
    printf '%s\n' "${excludes[@]}"
}

#######################################
# Check if a service:action combination is cacheable.
# Globals:
#   None
# Arguments:
#   service - AWS service name (e.g., "rds")
#   action - AWS action name (e.g., "describe-db-clusters")
# Outputs:
#   None
# Returns:
#   0 if cacheable, 1 if not cacheable
#######################################
is_cacheable() {
    local service="$1"
    local action="$2"
    
    # 除外ルールを読み込み
    local excludes=()
    while IFS= read -r line; do
        [[ -n "${line}" ]] && excludes+=("$line")
    done < <(load_cache_excludes)
    
    for rule in "${excludes[@]}"; do
        local rule_service="${rule%%:*}"
        local rule_action="${rule##*:}"
        
        # 完全一致
        if [[ "${rule_service}" == "${service}" ]] && [[ "${rule_action}" == "${action}" ]]; then
            return 1
        fi
        
        # サービスのワイルドカード: service:*
        if [[ "${rule_service}" == "${service}" ]] && [[ "${rule_action}" == "*" ]]; then
            return 1
        fi
        
        # アクションのワイルドカード: *:action
        if [[ "${rule_service}" == "*" ]] && [[ "${rule_action}" == "${action}" ]]; then
            return 1
        fi
        
        # 完全ワイルドカード: *:*
        if [[ "${rule_service}" == "*" ]] && [[ "${rule_action}" == "*" ]]; then
            return 1
        fi
    done
    
    return 0
}
