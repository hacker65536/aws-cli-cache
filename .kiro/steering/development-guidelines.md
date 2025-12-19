---
inclusion: always
---

# 開発ガイドライン

## テスト

### 実行コマンド

```bash
./tests/run_all_tests.sh      # 全テスト
./tests/test_performance.sh   # パフォーマンス
./tests/test_integration.sh   # 統合テスト
```

### 基準

- 全テスト合格を維持
- パフォーマンス: 2.2 倍以上の高速化維持

## 一貫性チェック

実装とドキュメントの整合性を確認:

1. SPECIFICATION.md と実装の一致
2. README.md と実装の一致
3. 環境変数のドキュメント統一

## プライバシー

### 禁止事項

- 個人情報（名前、メール、電話番号）
- AWS 固有情報（アカウント ID、アクセスキー）
- 組織固有情報（会社名、プロジェクト ID）
- システム固有情報（ホスト名、IP アドレス）

### 例示

```bash
# 良い例
aws_cached --profile my-profile rds describe-db-clusters

# 避ける例
aws_cached --profile company-prod-admin rds describe-db-clusters
```

## リリース

### バージョン管理

- 機能追加: マイナーバージョン
- バグ修正: パッチバージョン
- 破壊的変更: メジャーバージョン

### リリース前チェック

```bash
./tests/run_all_tests.sh  # テスト実行
bash -n aws_cache.sh      # 構文チェック
```
