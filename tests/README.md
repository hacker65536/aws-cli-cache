# AWS CLI Cache Tests

このディレクトリには、aws_cache.sh の包括的なテストスイートが含まれています。

## テストファイル

### 1. test_aws_cache.sh

**ユニットテスト** - AWS CLI に依存しない基本機能のテスト

- パラメータ抽出関数のテスト
- キャッシュ除外ルールのテスト
- ハッシュ生成のテスト
- キャッシュファイル操作のテスト
- 並行実行のテスト
- キャッシュ制限のテスト
- 統計機能のテスト

### 2. test_integration.sh

**統合テスト** - 実際の AWS CLI との統合テスト

- 基本的なキャッシュ動作（ヒット/ミス）
- 強制リフレッシュ機能
- キャッシュバイパス機能
- パラメータバリエーション
- パフォーマンス比較
- 並行実行
- TTL 期限切れ
- エラーハンドリング
- 統計機能

**前提条件**: AWS CLI がインストールされ、設定されている必要があります

### 3. test_performance.sh

**パフォーマンステスト** - 詳細なパフォーマンス測定

- 基本的なキャッシュパフォーマンス
- 大量データのパフォーマンス
- 並行実行パフォーマンス
- キャッシュサイズとパフォーマンスの関係
- メモリ使用量分析
- ディスク使用量とパフォーマンス

**前提条件**: AWS CLI がインストールされ、設定されている必要があります

### 4. run_all_tests.sh

**テストランナー** - すべてのテストを実行するメインスクリプト

## 使用方法

### すべてのテストを実行

```bash
./tests/run_all_tests.sh
```

### 特定のテストのみ実行

```bash
# ユニットテストのみ
./tests/run_all_tests.sh unit

# 統合テストのみ
./tests/run_all_tests.sh integration

# パフォーマンステストのみ
./tests/run_all_tests.sh performance

# 複数指定
./tests/run_all_tests.sh unit integration
```

### オプション

```bash
# 詳細出力
./tests/run_all_tests.sh --verbose

# 静寂モード（サマリーのみ）
./tests/run_all_tests.sh --quiet

# 統合テストをスキップ
./tests/run_all_tests.sh --no-integration

# パフォーマンステストをスキップ
./tests/run_all_tests.sh --no-performance

# ヘルプ表示
./tests/run_all_tests.sh --help
```

### 個別実行

```bash
# ユニットテスト
./tests/test_aws_cache.sh

# 統合テスト（AWS CLI必須）
./tests/test_integration.sh

# パフォーマンステスト（AWS CLI必須）
./tests/test_performance.sh
```

## 前提条件

### すべてのテスト

- Bash 4.0 以上
- 基本的な Unix コマンド（find, grep, awk, etc.）

### 統合テスト・パフォーマンステスト

- AWS CLI v1 または v2
- AWS 認証情報の設定（`aws configure`、環境変数、またはテスト設定ファイル）
- jq（JSON パース用、推奨）

### テスト設定ファイル（オプション）

テスト用の AWS 設定を分離するために、`tests/test-config.sh`ファイルを作成できます：

```bash
# サンプルファイルをコピー
cp tests/test-config.sh.example tests/test-config.sh

# 設定を編集
vim tests/test-config.sh
```

このファイルは`.gitignore`に含まれており、機密情報が誤ってコミットされることを防ぎます。

### AWS CLI 設定例

#### 方法 1: テスト設定ファイルを使用（推奨）

```bash
# サンプルファイルをコピー
cp tests/test-config.sh.example tests/test-config.sh

# 実際の設定値を入力
vim tests/test-config.sh
```

#### 方法 2: 直接 AWS CLI を設定

```bash
# AWS CLIの設定
aws configure

# または環境変数で設定
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

#### 方法 3: SSO 設定を使用

```bash
# test-config.shで設定
export AWS_CONFIG_FILE="/path/to/your/.aws/sso-config"
export AWS_PROFILE="your-sso-profile"
```

## テスト結果の見方

### 成功例

```
=== Test Summary ===
Passed: 25
Failed: 0
Total:  25

✓ All tests passed!
```

### 失敗例

```
=== Test Summary ===
Passed: 23
Failed: 2
Total:  25

Failed Tests:
  ✗ extract_profile with --profile
  ✗ Cache hit performance

✗ Some tests failed
```

## トラブルシューティング

### AWS CLI 関連のエラー

```bash
# AWS CLIの確認
aws --version
aws sts get-caller-identity

# 認証情報の確認
aws configure list
```

### 権限エラー

```bash
# 実行権限の付与
chmod +x tests/*.sh
```

### キャッシュディレクトリの問題

テストは一時ディレクトリを使用するため、通常は問題ありませんが、権限エラーが発生する場合：

```bash
# 一時ディレクトリの確認
ls -la /tmp/aws_cache_*test*

# 手動クリーンアップ
rm -rf /tmp/aws_cache_*test*
```

## CI/CD 統合

### GitHub Actions 例

```yaml
name: AWS Cache Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install AWS CLI
        run: |
          curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
          unzip awscliv2.zip
          sudo ./aws/install
      - name: Run Unit Tests
        run: ./tests/run_all_tests.sh --unit-only
      - name: Run Integration Tests
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          AWS_DEFAULT_REGION: us-east-1
        run: ./tests/run_all_tests.sh integration
```

## 開発者向け情報

### 新しいテストの追加

1. 適切なテストファイルに関数を追加
2. `run_all_tests.sh`の実行計画に含める（必要に応じて）
3. テストの命名規則に従う（`test_*`）

### テストヘルパー関数

- `assert_success`: コマンドの成功を確認
- `assert_failure`: コマンドの失敗を確認
- `assert_equals`: 値の一致を確認
- `assert_contains`: 文字列の包含を確認
- `assert_file_exists`: ファイルの存在を確認
- `assert_file_not_exists`: ファイルの非存在を確認

### デバッグ

```bash
# 詳細出力でテスト実行
./tests/run_all_tests.sh --verbose

# 特定のテスト関数のみ実行（テストファイル内で）
test_parameter_extraction
```
