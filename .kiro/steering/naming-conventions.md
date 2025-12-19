---
inclusion: always
---

# 命名規則

## 変数

### グローバル変数

- 環境変数: `AWS_CACHE_*`
- 内部変数: `CACHE_*`
- 形式: `UPPER_SNAKE_CASE`

### ローカル変数

- 形式: `lower_snake_case`
- 完全な単語を使用（略語は最小限）

### 真偽値フラグ

- `IS_`プレフィックス使用
- 例: `IS_EXCLUDES_LOADED`

### 配列

- `_RULES`または`_LIST`接尾辞
- 例: `DEFAULT_EXCLUDE_RULES`

## 関数

形式: `lower_snake_case`、動詞で開始

### 動詞の使い分け

| 動詞         | 用途               |
| ------------ | ------------------ |
| `extract_*`  | 既存データから抽出 |
| `generate_*` | 新規データ生成     |
| `get_*`      | データ取得         |
| `find_*`     | データ検索         |
| `is_*`       | 真偽値判定         |
| `check_*`    | 状態チェック       |
| `load_*`     | データ読み込み     |
| `write_*`    | データ書き込み     |
| `read_*`     | データ読み取り     |

## 簡潔性

文脈から明らかな単語は省略:

- `extract_service_name()` → `extract_service()`
- `extract_output_format()` → `extract_format()`
