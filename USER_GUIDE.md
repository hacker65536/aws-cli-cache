# AWS CLI Cache - 利用ガイド

## クイックスタート

### インストール

```bash
# リポジトリをクローン
git clone <repository-url>
cd aws-cli-cache

# 実行権限を付与
chmod +x aws_cache.sh

# シェル設定ファイルに追加
echo 'source /path/to/aws_cache.sh' >> ~/.bashrc
# または
echo 'source /path/to/aws_cache.sh' >> ~/.zshrc

# 設定を再読み込み
source ~/.bashrc  # または source ~/.zshrc
```

### 基本的な使い方

```bash
# 通常のAWS CLIコマンドの代わりにaws_cachedを使用
aws_cached rds describe-db-clusters

# エイリアスを設定すると便利
alias aws=aws_cached
aws rds describe-db-clusters
```

---

## 基本機能

### 1. キャッシュ付きでAWS CLIを実行

```bash
# 基本的な使用
aws_cached rds describe-db-clusters

# 特定のクラスターを指定
aws_cached rds describe-db-clusters --db-cluster-identifier my-cluster

# 異なるプロファイルを使用
aws_cached --profile production rds describe-db-instances

# 異なるリージョンを使用
aws_cached --region us-west-2 ec2 describe-instances
```

**動作**:
- 初回実行: AWS APIを呼び出し、結果をキャッシュ
- 2回目以降: キャッシュから結果を返す（高速）

---

## オプション

### --cache-ttl

キャッシュの有効期限を指定します。

```bash
# 5分間キャッシュ
aws_cached --cache-ttl 300 rds describe-db-clusters

# 1時間キャッシュ（デフォルト）
aws_cached --cache-ttl 3600 ec2 describe-instances

# 24時間キャッシュ
aws_cached --cache-ttl 86400 s3 ls
```

**使用例**:
- 頻繁に変更されるデータ: 短いTTL（300秒）
- あまり変更されないデータ: 長いTTL（3600秒以上）

### --force-refresh

キャッシュを無視して、最新のデータを取得します。

```bash
# キャッシュを更新
aws_cached --force-refresh rds describe-db-clusters

# デバッグ情報も表示
aws_cached --force-refresh --verbose rds describe-db-clusters
```

**使用例**:
- データが変更されたことが分かっている場合
- キャッシュが古くなった可能性がある場合

### --no-cache

このコマンドのみキャッシュをバイパスします。

```bash
# キャッシュを使用せずに実行
aws_cached --no-cache rds describe-db-clusters

# Write操作（自動的に--no-cacheと同じ動作）
aws_cached rds create-db-cluster --db-cluster-identifier new-cluster
```

**使用例**:
- 一時的にキャッシュを無効化したい場合
- リアルタイムのデータが必要な場合

### --verbose

キャッシュのヒット/ミス情報を表示します。

```bash
# デバッグ情報を表示
aws_cached --verbose rds describe-db-clusters

# 出力例:
# [CACHE] Miss: Executing AWS CLI
# [CACHE] Saved to: /path/to/cache/file (TTL: 3600s)
# または
# [CACHE] Hit: /path/to/cache/file
# [CACHE] Age: 120s, Remaining: 3480s, TTL: 3600s
```

**使用例**:
- キャッシュが正しく動作しているか確認
- パフォーマンスのデバッグ

---

## 管理コマンド

### キャッシュのクリア

```bash
# すべてのキャッシュをクリア
./aws_cache.sh clear all

# 特定のプロファイルのキャッシュをクリア
./aws_cache.sh clear my-profile

# 特定のサービスのキャッシュをクリア
./aws_cache.sh clear my-profile/rds

# 特定のリージョンのキャッシュをクリア
./aws_cache.sh clear my-profile/rds/us-east-1

# パターンマッチング
./aws_cache.sh clear my-cluster
```

### 期限切れキャッシュの削除

```bash
# 期限切れのキャッシュファイルを削除
./aws_cache.sh clean

# 出力例:
# === Cleaning Expired Cache Files ===
# Removed 42 expired cache files
# Freed space: 1024KB
```

**推奨**: cronで定期実行

```bash
# 毎日午前3時に実行
0 3 * * * /path/to/aws_cache.sh clean
```

### 統計情報の表示

```bash
# 全体の統計を表示
./aws_cache.sh stats

# 出力例:
# === AWS CLI Cache Statistics ===
# Cache Directory: /Users/user/.cache/aws-cli
# Default TTL: 3600s (60 minutes)
# 
# Total cache files: 150
# Total cache size: 25MB
# 
# By Profile:
#   my-profile: 100 files, 20MB
#     └─ rds: 50 files, 10MB
#     └─ ec2: 50 files, 10MB

# 特定のプロファイルの統計
./aws_cache.sh stats my-profile

# 特定のサービスの統計
./aws_cache.sh stats my-profile/rds
```

### メトリクスの表示

```bash
# キャッシュヒット率を表示
./aws_cache.sh metrics

# 出力例:
# === Cache Metrics ===
# 
# Total requests: 500
# Cache hits: 400
# Cache misses: 100
# Hit rate: 80%
# 
# Last 24 hours:
#   Requests: 150
#   Hits: 126
#   Misses: 24
#   Hit rate: 84%
```

**注意**: `AWS_CACHE_STATS=true` が必要

### ディレクトリ構造の表示

```bash
# キャッシュディレクトリの構造を表示
./aws_cache.sh tree

# treeコマンドがインストールされている場合、視覚的に表示
# ない場合は、findコマンドで表示
```

---

## 環境変数の設定

### 基本設定

```bash
# .bashrc または .zshrc に追加

# キャッシュディレクトリを変更
export AWS_CACHE_DIR="/custom/cache/dir"

# デフォルトTTLを変更（秒）
export AWS_CACHE_TTL=7200  # 2時間

# キャッシュサイズ制限
export AWS_CACHE_MAX_SIZE=2147483648  # 2GB
export AWS_CACHE_MAX_FILES=20000

# 統計記録を有効化
export AWS_CACHE_STATS=true

# 整合性チェックを有効化（セキュリティ重視）
export AWS_CACHE_VERIFY=true
```

### 環境別の推奨設定

#### 開発環境
```bash
# 高速化優先、大きめのキャッシュ
export AWS_CACHE_DIR="$HOME/.cache/aws-cli"
export AWS_CACHE_TTL=3600
export AWS_CACHE_MAX_SIZE=2147483648  # 2GB
export AWS_CACHE_MAX_FILES=20000
export AWS_CACHE_VERIFY=false
export AWS_CACHE_STATS=true
```

#### 本番環境（CI/CD）
```bash
# セキュリティ優先、小さめのキャッシュ
export AWS_CACHE_DIR="/tmp/aws-cli-cache"
export AWS_CACHE_TTL=1800  # 30分
export AWS_CACHE_MAX_SIZE=536870912  # 512MB
export AWS_CACHE_MAX_FILES=5000
export AWS_CACHE_VERIFY=true
export AWS_CACHE_STATS=true
```

#### 共有環境
```bash
# 容量制限厳格
export AWS_CACHE_DIR="$HOME/.cache/aws-cli"
export AWS_CACHE_TTL=1800
export AWS_CACHE_MAX_SIZE=268435456  # 256MB
export AWS_CACHE_MAX_FILES=2000
export AWS_CACHE_VERIFY=false
export AWS_CACHE_STATS=false
```

---

## キャッシュ除外ルール

### デフォルトで除外されるアクション

以下のアクションは自動的にキャッシュから除外されます：

- **Create系**: `create-*`, `run-*`
- **Update系**: `modify-*`, `update-*`
- **Delete系**: `delete-*`, `terminate-*`
- **実行系**: `invoke`, `publish`, `send-*`

### カスタム除外ルールの追加

```bash
# 除外ルールを表示
./aws_cache.sh excludes

# 除外ルールを追加
./aws_cache.sh add-exclude cloudwatch:describe-alarms

# 除外ルールを削除
./aws_cache.sh remove-exclude cloudwatch:describe-alarms

# 設定ファイルを直接編集
vim ~/.config/aws-cli/cache-exclude
```

**設定ファイル形式**:
```
# コメント行
service:action
cloudwatch:get-metric-data
s3:*
*:list-*
```

---

## 実用例

### 例1: ダッシュボードスクリプト

```bash
#!/bin/bash
source /path/to/aws_cache.sh

# 複数のAWSリソースを取得（キャッシュで高速化）
echo "=== RDS Clusters ==="
aws_cached rds describe-db-clusters --query 'DBClusters[*].DBClusterIdentifier'

echo "=== EC2 Instances ==="
aws_cached ec2 describe-instances --query 'Reservations[*].Instances[*].InstanceId'

echo "=== S3 Buckets ==="
aws_cached s3 ls
```

### 例2: 監視スクリプト

```bash
#!/bin/bash
source /path/to/aws_cache.sh

# 短いTTLで最新情報を取得
aws_cached --cache-ttl 60 cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBClusterIdentifier,Value=my-cluster \
    --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

### 例3: デプロイスクリプト

```bash
#!/bin/bash
source /path/to/aws_cache.sh

# デプロイ前: キャッシュを使用して現在の状態を確認
echo "Current state:"
aws_cached rds describe-db-clusters --db-cluster-identifier my-cluster

# デプロイ実行
echo "Deploying..."
aws rds modify-db-cluster \
    --db-cluster-identifier my-cluster \
    --apply-immediately

# デプロイ後: キャッシュを更新
echo "New state:"
aws_cached --force-refresh rds describe-db-clusters \
    --db-cluster-identifier my-cluster
```

### 例4: 並行実行

```bash
#!/bin/bash
source /path/to/aws_cache.sh

# 複数のリージョンを並行処理
for region in us-east-1 us-west-2 ap-northeast-1; do
    (
        echo "Checking $region..."
        aws_cached --region $region ec2 describe-instances
    ) &
done

wait
echo "All regions checked!"
```

---

## トラブルシューティング

### キャッシュが効かない

**症状**: 毎回AWS APIが呼ばれる

**確認事項**:
1. `--verbose` オプションで確認
   ```bash
   aws_cached --verbose rds describe-db-clusters
   ```

2. 除外ルールを確認
   ```bash
   ./aws_cache.sh excludes
   ```

3. キャッシュディレクトリを確認
   ```bash
   ls -la $AWS_CACHE_DIR
   ```

### キャッシュが古い

**症状**: 古いデータが返される

**解決方法**:
```bash
# 強制リフレッシュ
aws_cached --force-refresh rds describe-db-clusters

# または特定のキャッシュをクリア
./aws_cache.sh clear my-profile/rds
```

### ディスク容量不足

**症状**: キャッシュファイルが作成されない

**解決方法**:
```bash
# 期限切れキャッシュを削除
./aws_cache.sh clean

# またはすべてクリア
./aws_cache.sh clear all

# サイズ制限を調整
export AWS_CACHE_MAX_SIZE=536870912  # 512MB
```

### パフォーマンスが遅い

**症状**: キャッシュヒット時も遅い

**確認事項**:
1. 整合性チェックを無効化
   ```bash
   export AWS_CACHE_VERIFY=false
   ```

2. キャッシュファイル数を確認
   ```bash
   ./aws_cache.sh stats
   ```

3. 古いキャッシュを削除
   ```bash
   ./aws_cache.sh clean
   ```

---

## ベストプラクティス

### 1. エイリアスの設定

```bash
# .bashrc または .zshrc
alias aws=aws_cached
alias awsf='aws_cached --force-refresh'
alias awsv='aws_cached --verbose'
```

### 2. 定期的なクリーンアップ

```bash
# crontab -e
0 3 * * * /path/to/aws_cache.sh clean
```

### 3. プロジェクト別の設定

```bash
# プロジェクトディレクトリの .envrc (direnv使用)
export AWS_CACHE_DIR="$PWD/.aws-cache"
export AWS_CACHE_TTL=1800
export AWS_PROFILE=my-project
```

### 4. CI/CDでの使用

```yaml
# GitHub Actions
- name: Setup AWS Cache
  run: |
    source aws_cache.sh
    export AWS_CACHE_DIR=/tmp/aws-cache
    export AWS_CACHE_TTL=300

- name: Run deployment
  run: |
    aws_cached rds describe-db-clusters
```

### 5. 統計の活用

```bash
# 定期的にヒット率を確認
./aws_cache.sh metrics

# ヒット率が低い場合はTTLを調整
export AWS_CACHE_TTL=7200  # 2時間に延長
```

---

## FAQ

### Q: キャッシュはどこに保存されますか？

A: デフォルトでは `~/.cache/aws-cli` に保存されます。`AWS_CACHE_DIR` 環境変数で変更可能です。

### Q: キャッシュは自動的に削除されますか？

A: 期限切れのキャッシュは自動的には削除されません。`./aws_cache.sh clean` コマンドで削除してください。

### Q: Write操作もキャッシュされますか？

A: いいえ。Create/Update/Delete系の操作は自動的に除外されます。

### Q: 複数のプロセスで同時に使用できますか？

A: はい。並行実行に対応しています。

### Q: AWS CLI v1とv2の両方に対応していますか？

A: はい。両方に対応していますが、v2を推奨します。

### Q: キャッシュのセキュリティは？

A: ファイルはユーザーディレクトリに保存され、デフォルトのumask設定が適用されます。より高いセキュリティが必要な場合は `AWS_CACHE_VERIFY=true` を設定してください。

---

**作成者**: Kiro AI Assistant  
**作成日**: 2024年11月19日  
**バージョン**: 3.0.0
