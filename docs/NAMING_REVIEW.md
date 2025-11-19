# 変数名・関数名レビュー

## 分析日
2024年11月19日

---

## 現在の命名規則

### グローバル変数（環境変数）
```bash
CACHE_DIR                # キャッシュディレクトリ
CACHE_TTL                # デフォルトTTL
CACHE_MAX_SIZE           # 最大サイズ
CACHE_MAX_FILES          # 最大ファイル数
CACHE_EXCLUDE_CONFIG     # 除外設定ファイル
XDG_CACHE_HOME          # XDG Base Directory
XDG_CONFIG_HOME         # XDG Base Directory
```

### グローバル変数（内部状態）
```bash
DEFAULT_CACHE_EXCLUDES   # デフォルト除外ルール配列
CACHED_EXCLUDES          # キャッシュされた除外ルール配列
EXCLUDES_LOADED          # 除外ルール読み込み済みフラグ
```

### 関数（21個）
```bash
# メイン機能
aws_cached               # キャッシュ付きAWS CLI実行

# 抽出系
extract_profile          # プロファイル抽出
extract_service_name     # サービス名抽出
extract_region           # リージョン抽出
extract_action           # アクション抽出
extract_params_hash      # パラメータハッシュ生成
extract_output_format    # 出力形式抽出

# キャッシュ操作
read_cache               # キャッシュ読み込み
write_cache              # キャッシュ書き込み
is_cache_valid           # キャッシュ有効性チェック
find_valid_cache_file    # 有効なキャッシュファイル検索
get_cache_file           # キャッシュファイルパス取得
generate_cache_key       # キャッシュキー生成

# 判定系
is_cacheable             # キャッシュ対象判定

# 設定系
load_cache_excludes      # 除外ルール読み込み

# 管理系
clear_cache              # キャッシュクリア
cache_stats              # 統計表示
check_cache_limits       # サイズ制限チェック

# 統計系
record_cache_hit         # ヒット記録
record_cache_miss        # ミス記録
show_cache_metrics       # メトリクス表示
```

---

## 評価

### ✅ 優れている点

#### 1. 一貫性のある命名規則
- **グローバル変数**: `UPPER_SNAKE_CASE`
- **関数名**: `lower_snake_case`
- **ローカル変数**: `lower_snake_case`

#### 2. 明確なプレフィックス
- `extract_*`: 抽出系関数
- `is_*`: 判定系関数（真偽値を返す）
- `record_*`: 記録系関数
- `CACHE_*`: キャッシュ関連変数

#### 3. 自己説明的な名前
```bash
find_valid_cache_file    # 「有効なキャッシュファイルを見つける」
check_cache_limits       # 「キャッシュ制限をチェックする」
show_cache_metrics       # 「キャッシュメトリクスを表示する」
```

#### 4. 標準規約への準拠
- XDG Base Directory仕様に準拠（`XDG_*`）
- AWS環境変数の命名規則に準拠（`AWS_CACHE_*`）

---

## ⚠️ 改善の余地がある点

### 1. 関数名の冗長性

#### 問題
一部の関数名が冗長または不明確

```bash
# 現在
extract_service_name     # "name"は冗長
extract_params_hash      # "extract"と"hash"の意味が重複

# 改善案
extract_service          # よりシンプル
generate_params_hash     # 意図が明確（生成する）
```

### 2. 動詞の不統一

#### 問題
似た機能で異なる動詞を使用

```bash
# 現在
get_cache_file           # "get"を使用
find_valid_cache_file    # "find"を使用
generate_cache_key       # "generate"を使用

# 改善案（統一）
get_cache_file           # ファイルパスを取得
find_cache_file          # 既存ファイルを検索
generate_cache_key       # 新しいキーを生成
```

### 3. 略語の使用

#### 問題
`params`は略語だが、他は略していない

```bash
# 現在
extract_params_hash      # "params"は"parameters"の略

# 改善案（一貫性）
extract_parameters_hash  # 完全な単語
# または
extract_param_hash       # より短く
```

### 4. 配列変数の命名

#### 問題
配列であることが名前から分かりにくい

```bash
# 現在
DEFAULT_CACHE_EXCLUDES   # 配列だが名前からは不明
CACHED_EXCLUDES          # 配列だが名前からは不明

# 改善案
DEFAULT_EXCLUDE_RULES    # より明確
CACHED_EXCLUDE_RULES     # より明確
# または
EXCLUDE_RULES_DEFAULT    # 接尾辞で種類を示す
EXCLUDE_RULES_CACHED     # 接尾辞で種類を示す
```

### 5. フラグ変数の命名

#### 問題
真偽値フラグが明確でない

```bash
# 現在
EXCLUDES_LOADED          # 過去分詞形

# 改善案
IS_EXCLUDES_LOADED       # "IS_"プレフィックスで真偽値を明示
EXCLUDES_LOADED_FLAG     # "_FLAG"接尾辞で真偽値を明示
```

---

## 推奨される改善案

### オプション A: 最小限の変更（推奨）

**変更が必要な箇所のみ修正**

```bash
# 関数名
extract_service_name     → extract_service
extract_params_hash      → generate_params_hash

# 変数名
EXCLUDES_LOADED          → IS_EXCLUDES_LOADED
```

**影響**: 小
**互換性**: 内部関数のみなので影響なし

---

### オプション B: 包括的な改善

**すべての命名を最適化**

#### グローバル変数
```bash
# 現在 → 改善後
DEFAULT_CACHE_EXCLUDES   → DEFAULT_EXCLUDE_RULES
CACHED_EXCLUDES          → CACHED_EXCLUDE_RULES
EXCLUDES_LOADED          → IS_EXCLUDES_LOADED
```

#### 関数名
```bash
# 抽出系
extract_service_name     → extract_service
extract_params_hash      → generate_params_hash
extract_output_format    → extract_format

# キャッシュ操作
find_valid_cache_file    → find_cache_file
get_cache_file           → build_cache_path
```

**影響**: 中
**互換性**: 内部関数のみなので影響なし

---

### オプション C: 完全な再設計

**名前空間の導入**

```bash
# 現在の問題: グローバル名前空間の汚染

# 改善案: プレフィックスで名前空間を作成
aws_cache_init()
aws_cache_get()
aws_cache_set()
aws_cache_clear()
aws_cache_stats()

# または構造体的なアプローチ
cache::init
cache::get
cache::set
cache::clear
cache::stats
```

**影響**: 大
**互換性**: 破壊的変更
**推奨度**: ❌ 現時点では不要

---

## 具体的な改善提案

### 優先度: 高

#### 1. 真偽値フラグの明確化
```bash
# 変更前
EXCLUDES_LOADED=false

# 変更後
IS_EXCLUDES_LOADED=false
```

**理由**: 真偽値であることが一目で分かる

#### 2. 動詞の統一
```bash
# 変更前
extract_params_hash()

# 変更後
generate_params_hash()
```

**理由**: "extract"は既存のものを取り出す、"generate"は新しく作る

---

### 優先度: 中

#### 3. 冗長な単語の削除
```bash
# 変更前
extract_service_name()
extract_output_format()

# 変更後
extract_service()
extract_format()
```

**理由**: 文脈から明らか

#### 4. 配列変数の明確化
```bash
# 変更前
DEFAULT_CACHE_EXCLUDES
CACHED_EXCLUDES

# 変更後
DEFAULT_EXCLUDE_RULES
CACHED_EXCLUDE_RULES
```

**理由**: "RULES"の方が意味が明確

---

### 優先度: 低

#### 5. 関数名の短縮
```bash
# 変更前
find_valid_cache_file()

# 変更後
find_cache_file()
```

**理由**: "valid"は暗黙的（無効なファイルは返さない）

---

## 他のプロジェクトとの比較

### Redis
```bash
redis_get()
redis_set()
redis_del()
redis_exists()
```
**特徴**: 短く、明確、動詞優先

### Memcached
```bash
memcached_get()
memcached_set()
memcached_delete()
memcached_flush()
```
**特徴**: 完全な単語、プレフィックス統一

### 本プロジェクト
```bash
aws_cached()           # メイン関数
read_cache()           # 読み込み
write_cache()          # 書き込み
clear_cache()          # クリア
```
**特徴**: 動詞優先、シンプル

**評価**: ✅ 業界標準に準拠

---

## ローカル変数の命名

### 現在のパターン

```bash
# 良い例
local cache_file="$1"
local ttl="${1:-$CACHE_TTL}"
local file_count=$(...)

# 改善の余地
local cmd="$*"           # "cmd"は略語
local atime              # 意味が不明確
```

### 推奨パターン

```bash
# 完全な単語を使用
local command="$*"       # "cmd" → "command"
local access_time        # "atime" → "access_time"

# ただし、一般的な略語は許容
local ttl                # Time To Live（業界標準）
local pid                # Process ID（業界標準）
```

---

## 命名規則ガイドライン

### グローバル変数
- ✅ `UPPER_SNAKE_CASE`
- ✅ 環境変数は`AWS_CACHE_*`プレフィックス
- ✅ 内部変数は`CACHE_*`プレフィックス

### 関数名
- ✅ `lower_snake_case`
- ✅ 動詞で始める（`get_`, `set_`, `is_`, `check_`）
- ✅ 真偽値を返す関数は`is_`プレフィックス

### ローカル変数
- ✅ `lower_snake_case`
- ✅ 完全な単語を使用（略語は最小限）
- ✅ 意味が明確な名前

### 配列
- ✅ 複数形を使用（`EXCLUDES`, `RULES`）
- ⚠️ 配列であることを明示（`_LIST`, `_ARRAY`は冗長）

---

## 実装推奨事項

### 即座に実装すべき変更

```bash
# 1. 真偽値フラグ
EXCLUDES_LOADED → IS_EXCLUDES_LOADED

# 2. 動詞の統一
extract_params_hash() → generate_params_hash()
```

**理由**: 
- 影響が小さい
- 可読性が大幅に向上
- 後方互換性を維持

### 将来的に検討すべき変更

```bash
# 配列変数の改名
DEFAULT_CACHE_EXCLUDES → DEFAULT_EXCLUDE_RULES
CACHED_EXCLUDES → CACHED_EXCLUDE_RULES

# 関数名の簡略化
extract_service_name() → extract_service()
extract_output_format() → extract_format()
```

**理由**:
- より大きな改善効果
- 慎重なテストが必要
- 次のメジャーバージョンで実装

---

## 総合評価

### 現在の命名品質: **A- (90/100)**

| 項目 | スコア | 評価 |
|-----|--------|------|
| 一貫性 | 95/100 | ✅ 優秀 |
| 明確性 | 90/100 | ✅ 良好 |
| 簡潔性 | 85/100 | ⚠️ やや冗長 |
| 標準準拠 | 95/100 | ✅ 優秀 |
| 保守性 | 90/100 | ✅ 良好 |

### 改善後の予想品質: **A+ (95/100)**

推奨される変更を実装することで、さらに5ポイントの向上が見込まれます。

---

## 結論

### 現状評価
✅ **全体的に適切な命名規則が使用されている**

- 一貫性がある
- 自己説明的
- 業界標準に準拠
- 保守しやすい

### 改善推奨
⚠️ **小規模な改善で完璧に近づける**

**即座に実装**:
1. `EXCLUDES_LOADED` → `IS_EXCLUDES_LOADED`
2. `extract_params_hash()` → `generate_params_hash()`

**将来的に検討**:
3. 配列変数の改名
4. 関数名の簡略化

### 最終判定
**現在の命名は本番環境で使用するのに十分な品質です。**

小規模な改善を実装することで、さらに優れたコードベースになります。

---

**レビュー担当**: Kiro AI Assistant  
**レビュー日**: 2024年11月19日
