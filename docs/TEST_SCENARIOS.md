# AWS CLI Cache テストシナリオ

## 概要

`test_cache.sh` は AWS CLI キャッシュ機能の包括的なテストスイートです。単体テスト、統合テスト、パフォーマンステストを含む10のテストカテゴリで構成されています。

## テスト実行方法

```bash
# 実行権限を付与
chmod +x test_cache.sh

# テスト実行
./test_cache.sh
```

## テスト環境

- **テスト用キャッシュディレクトリ**: `/tmp/aws_cache_test_<PID>`
- **テスト用TTL**: 10秒（通常の3600秒より短く設定）
- **自動クリーンアップ**: テスト終了時に自動削除

## テストカテゴリ

### Test 1: Basic Functions（基本関数のテスト）

**目的**: 各種抽出関数が正しく動作することを確認

| テスト項目 | 検証内容 | 入力例 | 期待値 |
|-----------|---------|--------|--------|
| `extract_profile` | `--profile`オプションの抽出 | `--profile my-profile` | `my-profile` |
| `extract_profile` | プロファイル未指定時のデフォルト値 | (なし) | `default` または環境変数の値 |
| `extract_service_name` | サービス名の抽出 | `rds describe-db-clusters` | `rds` |
| `extract_region` | `--region`オプションの抽出 | `--region us-east-1` | `us-east-1` |
| `extract_region` | リージョン未指定時のデフォルト値 | (なし) | `global` または環境変数の値 |
| `extract_action` | アクション名の抽出 | `rds describe-db-clusters` | `describe-db-clusters` |
| `extract_output_format` | `--output`オプションの抽出 | `--output json` | `json` |
| `extract_output_format` | 出力形式未指定時のデフォルト値 | (なし) | `json` |

**検証方法**: 各関数に入力を与え、出力が期待値と一致するか確認

---

### Test 2: Cache Excludes（キャッシュ除外ルールのテスト）

**目的**: キャッシュ対象/非対象の判定が正しく動作することを確認

| テスト項目 | サービス:アクション | キャッシュ可否 | 理由 |
|-----------|-------------------|--------------|------|
| Read操作 | `rds:describe-db-clusters` | ✓ 可能 | 読み取り専用操作 |
| Write操作 | `rds:create-db-cluster` | ✗ 不可 | データ変更操作 |
| Invoke操作 | `lambda:invoke` | ✗ 不可 | 実行操作（副作用あり） |
| Identity取得 | `sts:get-caller-identity` | ✓ 可能 | 読み取り専用操作 |

**検証方法**: `is_cacheable()` 関数の戻り値（0=可能、1=不可）を確認

---

### Test 3: Cache File Operations（キャッシュファイル操作のテスト）

**目的**: ファイルの読み書きが正しく動作することを確認

| テスト項目 | 検証内容 |
|-----------|---------|
| ディレクトリ作成 | キャッシュディレクトリが正しく作成される |
| ファイル書き込み | `write_cache()` でファイルが作成される |
| ファイル読み込み | `read_cache()` で正しいデータが取得できる |

**検証方法**: 
1. テストデータを書き込み
2. ファイルの存在を確認
3. 読み込んだデータが元のデータと一致するか確認

---

### Test 4: Cache Key Generation（キャッシュキー生成のテスト）

**目的**: キャッシュキーとパラメータハッシュの一貫性を確認

| テスト項目 | 検証内容 |
|-----------|---------|
| キー一貫性 | 同じコマンドから同じキーが生成される |
| キー一意性 | 異なるコマンドから異なるキーが生成される |
| ハッシュ一貫性 | 同じパラメータから同じハッシュが生成される |
| ハッシュ一意性 | 異なるパラメータから異なるハッシュが生成される |

**検証方法**: 
- 同じ入力で複数回実行し、出力が同一であることを確認
- 異なる入力で実行し、出力が異なることを確認

**重要性**: キャッシュの正確性に直結する重要なテスト

---

### Test 5: Atomic Write (Concurrency)（アトミック書き込みのテスト）

**目的**: 並行実行時のファイル破損を防ぐ仕組みが機能することを確認

**テストシナリオ**:
1. 同じファイルに対して3つのプロセスが同時に書き込み
2. バックグラウンドで並行実行（`&`）
3. すべてのプロセスの完了を待機（`wait`）
4. ファイルが破損していないことを確認

**検証内容**:
- ファイルが存在する
- ファイル内容が `data1`、`data2`、`data3` のいずれか（破損していない）

**実装の仕組み**:
```bash
# 一時ファイルに書き込み → アトミックに移動
temp_file="${cache_file}.tmp.$$"
echo "$data" > "$temp_file"
mv -f "$temp_file" "$cache_file"
```

---

### Test 6: Cache File Path Generation（キャッシュファイルパス生成のテスト）

**目的**: 階層化されたディレクトリ構造が正しく生成されることを確認

**期待されるパス構造**:
```
$CACHE_DIR/
  └── {profile}/
      └── {service}/
          └── {region}/
              └── {action}/
                  └── {params_hash}/
                      └── {output_format}/
                          └── {cache_key}_{ttl}_{timestamp}_{pid}.cache
```

**検証内容**:
1. パスに必要な要素が含まれている
   - プロファイル名（`test`）
   - サービス名（`rds`）
   - リージョン名（`us-east-1`）
   - 出力形式（`json`）
   - TTL（`300`）
2. ディレクトリ構造が自動作成される

---

### Test 7: Cache Validity Check（キャッシュ有効性チェックのテスト）

**目的**: TTLに基づくキャッシュの有効期限判定が正しく動作することを確認

| テスト項目 | ファイル名形式 | 有効/無効 |
|-----------|--------------|----------|
| 有効なキャッシュ | `hash_3600_{現在時刻}_{pid}.cache` | ✓ 有効 |
| 期限切れキャッシュ | `hash_3600_{2時間前}_{pid}.cache` | ✗ 無効 |

**検証方法**:
- 現在時刻のタイムスタンプでファイルを作成 → 有効と判定されるべき
- 過去のタイムスタンプでファイルを作成 → 無効と判定されるべき

**計算式**: `expiry_time = timestamp + ttl > current_time`

---

### Test 8: Real AWS CLI Integration（実際のAWS CLI統合テスト）

**前提条件**: 
- AWS CLIがインストールされている
- AWS認証情報が設定されている

**テストシナリオ**:

#### 8-1. キャッシュミスのテスト
```bash
aws_cached --verbose sts get-caller-identity
```
- 初回実行時に `[CACHE] Miss` が表示される
- AWS APIが実際に呼び出される

#### 8-2. キャッシュヒットのテスト
```bash
aws_cached --verbose sts get-caller-identity
```
- 2回目実行時に `[CACHE] Hit` が表示される
- キャッシュから結果が返される（APIコールなし）

#### 8-3. 強制リフレッシュのテスト
```bash
aws_cached --verbose --force-refresh sts get-caller-identity
```
- `[CACHE] Force refresh` が表示される
- 既存キャッシュが削除される
- 新しいデータが取得される

#### 8-4. キャッシュバイパスのテスト
```bash
aws_cached --verbose --no-cache sts get-caller-identity
```
- `[CACHE] Bypass` が表示される
- キャッシュを使用せずに実行される

**スキップ条件**: AWS CLIが利用できない場合はスキップ

---

### Test 9: Concurrent Execution（並行実行のテスト）

**目的**: 複数プロセスが同時にキャッシュを使用しても安全であることを確認

**テストシナリオ**:
```bash
aws_cached sts get-caller-identity &
aws_cached sts get-caller-identity &
aws_cached sts get-caller-identity &
wait
```

**検証内容**:
1. **キャッシュファイルの作成**: 1つ以上のキャッシュファイルが作成される
2. **ファイルの整合性**: すべてのキャッシュファイルが有効なJSON形式である

**検証方法**:
```bash
# ファイル数をカウント
find "$CACHE_DIR" -name "*.cache" -type f | wc -l

# JSON形式の検証
jq . < cache_file
```

**重要性**: CI/CDパイプラインでの並行実行に対応するための重要なテスト

---

### Test 10: Performance Test（パフォーマンステスト）

**目的**: キャッシュによる高速化効果を測定

**測定項目**:

| 項目 | 説明 | コマンド |
|-----|------|---------|
| No cache | キャッシュなし（通常のAWS CLI） | `aws sts get-caller-identity` |
| First call | 初回実行（キャッシュミス） | `aws_cached sts get-caller-identity` |
| Cached call | 2回目実行（キャッシュヒット） | `aws_cached sts get-caller-identity` |

**測定方法**:
```bash
start=$(date +%s%N)
aws sts get-caller-identity > /dev/null 2>&1
end=$(date +%s%N)
time=$(( (end - start) / 1000000 ))  # ミリ秒に変換
```

**期待される結果**:
- キャッシュヒット時の実行時間 < 通常のAWS CLI実行時間
- 高速化率の表示（例: 217% = 2.17倍高速）

**実際の測定例**:
```
No cache:     671ms
First call:   481ms (cache miss)
Cached call:  309ms (cache hit)
✓ Cache is faster (217% of original time)
```

---

## テスト結果の見方

### 成功時の表示
```
✓ テスト名
```
- 緑色のチェックマーク
- テストが成功

### 失敗時の表示
```
✗ テスト名
  Expected: 期待値
  Actual: 実際の値
```
- 赤色のバツマーク
- 期待値と実際の値を表示

### スキップ時の表示
```
⊘ テスト名 (理由)
```
- 黄色の記号
- テストがスキップされた理由を表示

### サマリー
```
=== Test Summary ===
Passed: 29
Failed: 1
Total:  30
```

---

## テストヘルパー関数

### assert_success
```bash
assert_success "テスト名"
```
直前のコマンドの終了コードが0（成功）であることを確認

### assert_failure
```bash
assert_failure "テスト名"
```
直前のコマンドの終了コードが0以外（失敗）であることを確認

### assert_equals
```bash
assert_equals "期待値" "実際の値" "テスト名"
```
2つの値が等しいことを確認

### assert_file_exists
```bash
assert_file_exists "/path/to/file" "テスト名"
```
ファイルが存在することを確認

### assert_file_not_exists
```bash
assert_file_not_exists "/path/to/file" "テスト名"
```
ファイルが存在しないことを確認

---

## トラブルシューティング

### AWS CLI統合テストがスキップされる

**原因**: AWS CLIがインストールされていない、または認証情報が設定されていない

**解決方法**:
```bash
# AWS CLIのインストール確認
which aws

# 認証情報の設定確認
aws sts get-caller-identity
```

### 環境依存のテスト失敗

**原因**: `AWS_PROFILE`や`AWS_REGION`などの環境変数が設定されている

**解決方法**:
```bash
# 環境変数をクリアして実行
unset AWS_PROFILE AWS_REGION
./test_cache.sh
```

### パフォーマンステストで高速化が確認できない

**原因**: 
- ネットワークが非常に高速
- キャッシュのオーバーヘッドが大きい
- テスト環境の負荷が高い

**対処**: 警告として表示されるが、機能的には問題なし

---

## テストのカスタマイズ

### TTLの変更
```bash
# test_cache.sh の以下の行を編集
export AWS_CACHE_TTL=10  # 任意の秒数に変更
```

### テスト用キャッシュディレクトリの変更
```bash
# test_cache.sh の以下の行を編集
TEST_CACHE_DIR="/tmp/aws_cache_test_$$"  # 任意のパスに変更
```

### 特定のテストのみ実行
```bash
# test_cache.sh を編集して不要なテストをコメントアウト
# または、個別の関数を直接呼び出し
source ./aws_cache.sh
extract_profile "rds describe-db-clusters --profile test"
```

---

## CI/CD統合

### GitHub Actions での使用例
```yaml
- name: Run AWS Cache Tests
  run: |
    chmod +x test_cache.sh
    ./test_cache.sh
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

### 終了コード
- `0`: すべてのテスト成功
- `1`: 1つ以上のテスト失敗

---

## テストカバレッジ

| カテゴリ | カバー範囲 |
|---------|-----------|
| 単体テスト | 基本関数、キャッシュキー生成、ファイル操作 |
| 統合テスト | AWS CLI連携、キャッシュヒット/ミス |
| 並行性テスト | アトミック書き込み、並行実行 |
| パフォーマンステスト | 実行時間測定、高速化率 |

**総テスト数**: 約30テスト（環境により変動）

---

## まとめ

`test_cache.sh` は以下を保証します：

1. ✓ 基本機能の正確性
2. ✓ キャッシュの一貫性
3. ✓ 並行実行時の安全性
4. ✓ AWS CLI統合の正常動作
5. ✓ パフォーマンスの向上

これにより、本番環境での安全な使用が保証されます。
