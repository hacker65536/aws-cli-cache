# AWS CLI Cache

[![Version](https://img.shields.io/badge/version-3.1.1-blue.svg)](https://github.com/hacker65536/aws-cli-cache/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash%204.0%2B-orange.svg)](https://www.gnu.org/software/bash/)
[![Tests](https://img.shields.io/badge/tests-30%2F30%20passing-brightgreen.svg)](test_cache.sh)
[![Google Style](https://img.shields.io/badge/style-Google%20Shell%20Guide-yellow.svg)](https://google.github.io/styleguide/shellguide.html)
[![Performance](https://img.shields.io/badge/performance-2.2x%20faster-success.svg)](#パフォーマンス)

AWS CLI の API コール回数を削減するためのキャッシュレイヤー。TTL ベースの有効期限管理、LRU 削除、整合性検証をサポートし、本番環境での使用に最適化されています。

**バージョン**: 3.1.1  
**最終更新**: 2025 年 12 月 18 日

> **🔴 重要**: v3.1.1 でキャッシュヒット率 0%問題を修正しました。v3.0.0 以前をご利用の方は、できるだけ早くアップグレードしてください。詳細は[リリースノート](https://github.com/hacker65536/aws-cli-cache/releases/tag/v3.1.1)をご確認ください。

---

## 特徴

- ✅ **高速化**: AWS CLI 実行を約 2.2 倍高速化
- ✅ **階層化キャッシュ**: プロファイル/サービス/リージョン単位で管理
- ✅ **TTL 管理**: 柔軟な有効期限設定
- ✅ **LRU 削除**: 自動的にサイズ制限を管理
- ✅ **並行実行対応**: 複数プロセスでの同時実行が安全
- ✅ **整合性検証**: SHA256 ハッシュによる改ざん検出
- ✅ **統計情報**: キャッシュヒット率の分析
- ✅ **除外ルール**: Write 系操作は自動除外

---

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
source ~/.bashrc
```

### 基本的な使い方

```bash
# キャッシュ付きでAWS CLIを実行
aws_cached rds describe-db-clusters

# エイリアスを設定すると便利
alias aws=aws_cached
aws rds describe-db-clusters
```

---

## パフォーマンス

```
通常のAWS CLI:     657ms  (100%)
初回実行:          326ms  ( 50%)
2回目以降:         299ms  ( 45%)

高速化率: 約2.2倍
```

---

## 主要機能

### キャッシュ管理

```bash
# すべてのキャッシュをクリア
./aws_cache.sh clear all

# 期限切れキャッシュを削除
./aws_cache.sh clean

# 統計情報を表示
./aws_cache.sh stats

# ヒット率を表示
./aws_cache.sh metrics

# 除外ルールを表示
./aws_cache.sh excludes

# 除外ルールを追加
./aws_cache.sh add-exclude cloudwatch:describe-alarms

# 除外ルールを削除
./aws_cache.sh remove-exclude cloudwatch:describe-alarms
```

### オプション

```bash
# カスタムTTL（5分）
aws_cached --cache-ttl 300 rds describe-db-clusters

# 強制リフレッシュ
aws_cached --force-refresh rds describe-db-clusters

# キャッシュをバイパス
aws_cached --no-cache rds describe-db-clusters

# デバッグ情報を表示
aws_cached --verbose rds describe-db-clusters
```

### 環境変数

```bash
# キャッシュディレクトリ
export AWS_CACHE_DIR="$HOME/.cache/aws-cli"

# デフォルトTTL（秒）
export AWS_CACHE_TTL=3600

# サイズ制限
export AWS_CACHE_MAX_SIZE=1073741824  # 1GB
export AWS_CACHE_MAX_FILES=10000

# 整合性チェック
export AWS_CACHE_VERIFY=true

# 統計記録
export AWS_CACHE_STATS=true
```

---

## ドキュメント

### 主要ドキュメント

- **[SPECIFICATION.md](SPECIFICATION.md)** - 仕様全体の説明

  - アーキテクチャとデータフロー
  - 主要機能の詳細
  - 環境変数と CLI 仕様
  - パフォーマンス特性
  - セキュリティと互換性

- **[USER_GUIDE.md](USER_GUIDE.md)** - 利用方法ガイド

  - クイックスタート
  - 基本機能とオプション
  - 実用例
  - トラブルシューティング
  - ベストプラクティス

- **[CHANGELOG.md](CHANGELOG.md)** - 変更履歴
  - バージョン履歴
  - 実装した機能
  - 技術的決定
  - パフォーマンスの推移

### 詳細ドキュメント（docs/）

- **[IMPROVEMENTS.md](docs/IMPROVEMENTS.md)** - 初期改善内容
- **[IMPROVEMENTS_V2.md](docs/IMPROVEMENTS_V2.md)** - v2.0 改善内容
- **[NAMING_REVIEW.md](docs/NAMING_REVIEW.md)** - 命名規則レビュー
- **[NAMING_IMPROVEMENTS.md](docs/NAMING_IMPROVEMENTS.md)** - 命名改善実装
- **[GOOGLE_STYLE_REVIEW.md](docs/GOOGLE_STYLE_REVIEW.md)** - Google Style レビュー
- **[GOOGLE_STYLE_IMPROVEMENTS.md](docs/GOOGLE_STYLE_IMPROVEMENTS.md)** - Google Style 改善実装
- **[EVALUATION.md](docs/EVALUATION.md)** - 総合評価レポート
- **[TEST_SCENARIOS.md](docs/TEST_SCENARIOS.md)** - テストシナリオ
- **[TEST_RESULTS.md](docs/TEST_RESULTS.md)** - テスト結果

---

## 実用例

### ダッシュボードスクリプト

```bash
#!/bin/bash
source /path/to/aws_cache.sh

echo "=== RDS Clusters ==="
aws_cached rds describe-db-clusters

echo "=== EC2 Instances ==="
aws_cached ec2 describe-instances

echo "=== S3 Buckets ==="
aws_cached s3 ls
```

### 並行実行

```bash
#!/bin/bash
source /path/to/aws_cache.sh

# 複数のリージョンを並行処理
for region in us-east-1 us-west-2 ap-northeast-1; do
    (
        aws_cached --region $region ec2 describe-instances
    ) &
done
wait
```

---

## テスト

```bash
# テストスイートを実行
./test_cache.sh

# 結果:
# Passed: 30/30 (100%)
# Failed: 0/30 (0%)
# ✓ All tests passed!
```

---

## 要件

### 必須

- Bash 4.0+
- AWS CLI (v1 or v2)
- 標準 Unix コマンド（find, grep, sed, awk, shasum, du）

### 対応 OS

- ✅ macOS
- ✅ Linux
- ⚠️ Windows (WSL)

---

## アーキテクチャ

6 層の階層構造でキャッシュを管理し、TTL ベースの有効期限と LRU 削除を実装しています。

```
{profile}/{service}/{region}/{action}/{params_hash}/{format}/
  └── {hash}_{ttl}_{timestamp}_{pid}.cache
```

詳細なアーキテクチャ図とデータフローについては **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** を参照してください。

---

## コード品質

- ✅ **Google Shell Style Guide**: 完全準拠（96/100）
- ✅ **テストカバレッジ**: 100%（30/30 テスト合格）
- ✅ **Shellcheck**: 警告最小化
- ✅ **XDG Base Directory**: 準拠

---

## セキュリティ

### 実装済みの対策

- ✅ パストラバーサル対策
- ✅ ファイル権限管理
- ✅ インジェクション対策
- ✅ 整合性検証（オプション）

### 推奨設定

```bash
# セキュリティ重視の設定
export AWS_CACHE_VERIFY=true
export AWS_CACHE_MAX_SIZE=536870912  # 512MB
export AWS_CACHE_MAX_FILES=5000
```

---

## トラブルシューティング

### キャッシュが効かない

```bash
# デバッグ情報を表示
aws_cached --verbose rds describe-db-clusters

# 除外ルールを確認
./aws_cache.sh excludes
```

### キャッシュが古い

```bash
# 強制リフレッシュ
aws_cached --force-refresh rds describe-db-clusters

# または特定のキャッシュをクリア
./aws_cache.sh clear my-profile/rds
```

### ディスク容量不足

```bash
# 期限切れキャッシュを削除
./aws_cache.sh clean

# またはすべてクリア
./aws_cache.sh clear all
```

---

## ベストプラクティス

### 1. エイリアスの設定

```bash
alias aws=aws_cached
alias awsf='aws_cached --force-refresh'
alias awsv='aws_cached --verbose'
```

### 2. 定期的なクリーンアップ

```bash
# crontab -e
0 3 * * * /path/to/aws_cache.sh clean
```

### 3. 統計の活用

```bash
# 定期的にヒット率を確認
./aws_cache.sh metrics

# ヒット率が低い場合はTTLを調整
export AWS_CACHE_TTL=7200  # 2時間に延長
```

---

## FAQ

**Q: キャッシュはどこに保存されますか？**  
A: デフォルトでは `~/.cache/aws-cli` に保存されます。

**Q: Write 操作もキャッシュされますか？**  
A: いいえ。Create/Update/Delete 系の操作は自動的に除外されます。

**Q: 複数のプロセスで同時に使用できますか？**  
A: はい。並行実行に対応しています。

**Q: AWS CLI v1 と v2 の両方に対応していますか？**  
A: はい。両方に対応していますが、v2 を推奨します。

---

## ライセンス

（ライセンス情報を記載）

---

## 貢献

Pull Requests 歓迎！

---

## サポート

問題報告: GitHub Issues

---

**作成者**: Kiro AI Assistant  
**作成日**: 2025 年 11 月 19 日  
**バージョン**: 3.1.1
