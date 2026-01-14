# AWS CLI Cache - キャッシュ機構の詳細

このドキュメントでは、AWS CLI Cache のキャッシュ機構について、ハッシュ生成からキャッシュヒット判定までの全体像を詳しく説明します。

## 目次

1. [概要](#概要)
2. [コマンド実行の流れ](#コマンド実行の流れ)
3. [パラメータ抽出フェーズ](#パラメータ抽出フェーズ)
4. [ハッシュ生成フェーズ](#ハッシュ生成フェーズ)
5. [キャッシュパス構築](#キャッシュパス構築)
6. [キャッシュヒット判定](#キャッシュヒット判定)
7. [リージョン解決の詳細](#リージョン解決の詳細)
8. [2 種類のキャッシュ](#2種類のキャッシュ)
9. [具体例](#具体例)

---

## 概要

AWS CLI Cache は、AWS CLI コマンドの実行結果をファイルシステムにキャッシュすることで、同じクエリの繰り返し実行を高速化します。

### キャッシュの種類

| 種類                   | 保存場所 | 保存内容                            | ライフサイクル                    | 速度           |
| ---------------------- | -------- | ----------------------------------- | --------------------------------- | -------------- |
| **ファイルキャッシュ** | ディスク | AWS API レスポンス                  | TTL 期限まで（デフォルト 1 時間） | 高速（30ms）   |
| **メモリキャッシュ**   | メモリ   | プロファイル → リージョンマッピング | シェルセッション中                | 超高速（<1ms） |

---

## コマンド実行の流れ

```bash
aws_cached rds describe-db-clusters --region ap-northeast-1
```

このコマンドが実行されると、以下の処理が順次行われます：

```
1. パラメータ抽出
   ├─ プロファイル抽出
   ├─ サービス抽出
   ├─ リージョン解決
   ├─ アクション抽出
   └─ 出力形式抽出

2. ハッシュ生成
   ├─ パラメータハッシュ（16文字）
   └─ キャッシュキー（64文字）

3. キャッシュパス構築
   └─ {profile}/{service}/{region}/{action}/{params_hash}/{format}/

4. キャッシュヒット判定
   ├─ ファイル検索
   ├─ TTLチェック
   └─ ヒット/ミス判定

5. 結果返却
   ├─ ヒット: キャッシュファイル読み込み
   └─ ミス: AWS CLI実行 → キャッシュ保存
```

---

## パラメータ抽出フェーズ

### 1. プロファイル抽出 (`extract_profile()`)

```bash
入力: rds describe-db-clusters --region ap-northeast-1
処理: --profile オプションまたは環境変数から取得
結果: "my-aws-profile"
```

**優先順位:**

1. `--profile` オプション
2. `AWS_PROFILE` 環境変数
3. `AWS_DEFAULT_PROFILE` 環境変数
4. デフォルト値: `"default"`

### 2. サービス抽出 (`extract_service()`)

```bash
入力: rds describe-db-clusters --region ap-northeast-1
処理: 最初の引数を取得
結果: "rds"
```

### 3. リージョン解決 (`extract_region()` → `resolve_region()`)

```bash
入力: rds describe-db-clusters --region ap-northeast-1
処理: 優先順位で解決
  1. --region オプション → "ap-northeast-1" ✓
  2. AWS_REGION 環境変数
  3. AWS_DEFAULT_REGION 環境変数
  4. プロファイルの設定ファイル (~/.aws/config)
結果: "ap-northeast-1"
```

**重要:** `--region`オプションがない場合でも、プロファイルから解決されるため、**解決後のリージョンは同じ**になります。

### 4. アクション抽出 (`extract_action()`)

```bash
入力: rds describe-db-clusters --region ap-northeast-1
処理: サービス名の次の引数を取得
結果: "describe-db-clusters"
```

### 5. 出力形式抽出 (`extract_format()`)

```bash
入力: rds describe-db-clusters --region ap-northeast-1
処理: --output オプションまたはデフォルト
結果: "json"
```

---

## ハッシュ生成フェーズ

### パラメータハッシュ (`generate_params_hash()`)

**目的:** 同じディレクトリ内でパラメータの違いを識別

```bash
入力コマンド: rds describe-db-clusters --region ap-northeast-1

# ステップ1: オプション除外
フィルタ前: "rds describe-db-clusters --region ap-northeast-1"
フィルタ後: "rds describe-db-clusters"
# --region, --profile, --output を除外

# ステップ2: ハッシュ化（SHA256の最初の16文字）
結果: "5c203c45a1b531cb"
```

**除外されるオプション:**

- `--region` : リージョンはディレクトリパスで分離
- `--profile` : プロファイルはディレクトリパスで分離
- `--output` : 出力形式はディレクトリパスで分離

### キャッシュキー (`generate_cache_key()`)

**目的:** ファイル名として使用（同じパラメータなら同じファイル）

```bash
入力コマンド: rds describe-db-clusters --region ap-northeast-1

# ステップ1: オプション除外（params_hashと同じ処理）
フィルタ前: "rds describe-db-clusters --region ap-northeast-1"
フィルタ後: "rds describe-db-clusters"

# ステップ2: ハッシュ化（SHA256の完全な64文字）
結果: "5c203c45a1b531cbe69a23c27b8a2f6a9a14a7c7045deb4b84af18db1458e0b0"
```

**重要な設計:** `generate_cache_key()`も`--region`を除外するため、オプション指定方法に関わらず同じキーが生成されます。

---

## キャッシュパス構築

### ディレクトリ構造（6 層）

```
{CACHE_DIR}/
  {profile}/
    {service}/
      {region}/          ← 解決されたリージョン
        {action}/
          {params_hash}/
            {format}/
```

### 実際のパス例

```bash
# コマンド1: --region あり
aws_cached rds describe-db-clusters --region ap-northeast-1

# コマンド2: --region なし（プロファイルから解決）
aws_cached rds describe-db-clusters

# 両方とも同じパスになる:
~/.cache/aws-cli/
  my-aws-profile/
    rds/
      ap-northeast-1/    ← 両方とも同じリージョンに解決
        describe-db-clusters/
          5c203c45a1b531cb/    ← 同じparams_hash
            json/
```

### ファイル名

```
{cache_key}_{ttl}_{pid}.cache
```

**例:**

```
5c203c45a1b531cbe69a23c27b8a2f6a9a14a7c7045deb4b84af18db1458e0b0_3600_12345.cache
```

**構成要素:**

- `cache_key`: 64 文字の SHA256 ハッシュ（パラメータの識別）
- `ttl`: 3600 秒（1 時間）
- `pid`: プロセス ID（並行実行時の衝突回避）

---

## キャッシュヒット判定

### 検索処理 (`find_valid_cache_file()`)

```bash
# ステップ1: ディレクトリパスを構築
cache_path = "{CACHE_DIR}/{profile}/{service}/{region}/{action}/{params_hash}/{format}/"

# ステップ2: 該当ディレクトリ内でcache_keyで始まるファイルを検索
pattern = "{cache_key}_*.cache"

# ステップ3: 最新のファイルを取得（ls -t でソート）
latest_file = ls -t "$cache_path/${cache_key}_"*.cache | head -n 1

# ステップ4: TTLチェック
file_mtime = ファイルの変更時刻
file_ttl = ファイル名から抽出したTTL
current_time = 現在時刻

if (current_time < file_mtime + file_ttl):
    return latest_file  # キャッシュヒット
else:
    return 1  # 期限切れ
```

### TTL チェックの詳細

```bash
# ファイル名から情報を抽出
filename: "5c203c45a1b531cb...e0b0_3600_12345.cache"
          ↓
cache_key: "5c203c45a1b531cb...e0b0"
ttl: 3600
pid: 12345

# 有効期限の計算
file_mtime = 1704067200  # ファイルの変更時刻（エポック秒）
file_ttl = 3600          # TTL（秒）
expiry_time = 1704070800 # file_mtime + file_ttl

current_time = 1704068000

if (expiry_time > current_time):
    # 1704070800 > 1704068000 → true
    # キャッシュヒット！
```

---

## リージョン解決の詳細

### `--region`オプションが渡されなかった場合の処理

#### 1. リージョン解決の優先順位

```bash
resolve_region() {
    # 優先順位1: --region オプション
    if [コマンドに--regionがある]; then
        return リージョン値
    fi

    # 優先順位2: AWS_REGION 環境変数
    if [[ -n "${AWS_REGION:-}" ]]; then
        return $AWS_REGION
    fi

    # 優先順位3: AWS_DEFAULT_REGION 環境変数
    if [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then
        return $AWS_DEFAULT_REGION
    fi

    # 優先順位4: プロファイルの設定ファイルから取得
    profile=$(extract_profile "$@")
    region=$(get_profile_region "$profile")
    return $region
}
```

#### 2. プロファイルからのリージョン取得 (`get_profile_region()`)

```bash
get_profile_region() {
    local profile="$1"  # "my-aws-profile"

    # ステップ1: メモリキャッシュをチェック（技術的制約により現在は機能せず）
    if [[ -n "${_PROFILE_REGION_CACHE[$profile]:-}" ]]; then
        echo "${_PROFILE_REGION_CACHE[$profile]}"
        return 0
    fi

    # ステップ2: 設定ファイルのパスを取得
    config_file="~/.aws/config"

    # ステップ3: AWKで高速検索（200ms → 12ms）
    found_region=$(awk -v prof="$profile" '
        BEGIN { pattern = "^\\[profile[[:space:]]+" prof "\\]$" }

        # プロファイルセクションを見つける
        $0 ~ pattern { in_section=1; next }

        # 別のセクションに入ったら終了
        /^\[/ { in_section=0 }

        # プロファイルセクション内でregionを見つける
        in_section && /^[[:space:]]*region[[:space:]]*=/ {
            sub(/^[[:space:]]*region[[:space:]]*=[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            print
            exit  # 見つかったら即終了（高速化）
        }
    ' "$config_file")

    # ステップ4: 結果を返す
    echo "$found_region"
}
```

#### 3. 設定ファイルの例

```ini
[profile my-aws-profile]
sso_session = my-sso
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = ap-northeast-1
output = json

[profile dev-profile]
region = us-west-2
output = json
```

---

## 2 種類のキャッシュ

### ファイルキャッシュ（主要な高速化手段）

**保存場所:** `~/.cache/aws-cli/`

**保存内容:** AWS API レスポンス（JSON）

**ライフサイクル:** TTL 期限まで（デフォルト 1 時間）

**効果:**

```
初回: AWS API呼び出し（2000ms）
2回目以降: ファイル読み込み（30ms）
高速化率: 約67倍
```

### メモリキャッシュ（技術的制約あり）

**保存場所:** シェルのメモリ内（連想配列 `_PROFILE_REGION_CACHE`）

**保存内容:** プロファイル → リージョンのマッピング

**ライフサイクル:** シェルセッション中のみ

**技術的制約:**

コマンド置換`$()`はサブシェルで実行されるため、関数内でのグローバル変数への代入は親シェルに反映されません。

```bash
# これは動作しない
region=$(get_profile_region "$profile")
# ↑ サブシェルで実行されるため、関数内の
#    _PROFILE_REGION_CACHE[$profile]="$region"
#    は親シェルに反映されない
```

**実際の効果:**

メモリキャッシュは現在機能していませんが、`awk`による高速検索（200ms→12ms）により、十分な性能改善が達成されています。

---

## 具体例

### 例 1: 同じコマンドを 2 回実行

```bash
# 1回目: キャッシュミス
$ time aws_cached rds describe-db-clusters --region ap-northeast-1

処理内訳:
  1. パラメータ抽出: 5ms
  2. リージョン解決: 12ms（設定ファイル読み込み）
  3. ハッシュ生成: 2ms
  4. キャッシュ検索: 5ms（ファイルなし）
  5. AWS CLI実行: 2000ms
  6. キャッシュ保存: 10ms
合計: 2034ms

# 2回目: キャッシュヒット
$ time aws_cached rds describe-db-clusters --region ap-northeast-1

処理内訳:
  1. パラメータ抽出: 5ms
  2. リージョン解決: 12ms
  3. ハッシュ生成: 2ms
  4. キャッシュ検索: 5ms（ファイル発見）
  5. キャッシュ読み込み: 20ms
合計: 44ms

高速化率: 約46倍
```

### 例 2: `--region`オプションの有無

```bash
# コマンドA: --region あり
$ aws_cached rds describe-db-clusters --region ap-northeast-1

抽出結果:
  profile: my-aws-profile
  service: rds
  region: ap-northeast-1 (--regionから)
  action: describe-db-clusters
  format: json

ハッシュ生成:
  フィルタ後: "rds describe-db-clusters"
  params_hash: 5c203c45a1b531cb
  cache_key: 5c203c45a1b531cbe69a23c27b8a2f6a9a14a7c7045deb4b84af18db1458e0b0

キャッシュパス:
  ~/.cache/aws-cli/my-aws-profile/rds/ap-northeast-1/
    describe-db-clusters/5c203c45a1b531cb/json/
    5c203c45a1b531cbe69a23c27b8a2f6a9a14a7c7045deb4b84af18db1458e0b0_3600_12345.cache
```

```bash
# コマンドB: --region なし
$ aws_cached rds describe-db-clusters

抽出結果:
  profile: my-aws-profile
  service: rds
  region: ap-northeast-1 (プロファイルから解決) ← 同じ！
  action: describe-db-clusters
  format: json

ハッシュ生成:
  フィルタ後: "rds describe-db-clusters" ← 同じ！
  params_hash: 5c203c45a1b531cb ← 同じ！
  cache_key: 5c203c45a1b531cbe69a23c27b8a2f6a9a14a7c7045deb4b84af18db1458e0b0 ← 同じ！

キャッシュパス:
  ~/.cache/aws-cli/my-aws-profile/rds/ap-northeast-1/
    describe-db-clusters/5c203c45a1b531cb/json/
    5c203c45a1b531cbe69a23c27b8a2f6a9a14a7c7045deb4b84af18db1458e0b0_3600_12345.cache
  ← 完全に同じファイル！
```

**結果:** コマンド A で作成されたキャッシュを、コマンド B が再利用できます。

### 例 3: 異なるリージョン

```bash
# リージョン1: ap-northeast-1
$ aws_cached rds describe-db-clusters --region ap-northeast-1

キャッシュパス:
  ~/.cache/aws-cli/my-aws-profile/rds/ap-northeast-1/...

# リージョン2: us-east-1
$ aws_cached rds describe-db-clusters --region us-east-1

キャッシュパス:
  ~/.cache/aws-cli/my-aws-profile/rds/us-east-1/...
  ↑ 異なるディレクトリ → 別のキャッシュ
```

### 例 4: 異なるパラメータ

```bash
# パラメータなし
$ aws_cached rds describe-db-clusters

params_hash: 5c203c45a1b531cb
cache_key: 5c203c45a1b531cbe69a23c27b8a2f6a9a14a7c7045deb4b84af18db1458e0b0

# パラメータあり
$ aws_cached rds describe-db-clusters --db-cluster-identifier my-cluster

params_hash: a7f3e9d2c8b4f1a6  ← 異なる
cache_key: a7f3e9d2c8b4f1a6e5c3d7b9f2a8e4c6d1b5a9f3e7c2d8b4f1a6e5c3d7b9f2a8  ← 異なる

→ 異なるキャッシュファイルが作成される
```

---

## キャッシュヒットの仕組み

```
1回目: aws_cached rds describe-db-clusters --region ap-northeast-1
  ↓
  キャッシュ検索
  ↓
  ファイルなし → キャッシュミス
  ↓
  AWS CLI実行（2000ms）
  ↓
  キャッシュファイル作成
  ~/.cache/aws-cli/my-aws-profile/rds/ap-northeast-1/
    describe-db-clusters/5c203c45a1b531cb/json/
    5c203c45a1b531cbe69a23c27b8a2f6a9a14a7c7045deb4b84af18db1458e0b0_3600_12345.cache

2回目: aws_cached rds describe-db-clusters
  ↓
  リージョン解決: ap-northeast-1（プロファイルから）
  ↓
  ディレクトリパス構築: .../ap-northeast-1/describe-db-clusters/5c203c45a1b531cb/json/
  ↓
  ファイル検索: 5c203c45a1b531cbe69a23c27b8a2f6a9a14a7c7045deb4b84af18db1458e0b0_*.cache
  ↓
  ファイル発見！
  ↓
  TTLチェック: OK（3600秒以内）
  ↓
  キャッシュヒット（30ms）
```

---

## 設計の利点

### 1. ディレクトリ構造による分離

- **プロファイル別**: 異なる AWS アカウントのデータが混在しない
- **リージョン別**: 同じリソース名でもリージョンが違えば別キャッシュ
- **サービス別**: 管理しやすく、削除も容易

### 2. ハッシュによる識別

- **params_hash**: ディレクトリ名として使用（短い 16 文字）
- **cache_key**: ファイル名として使用（完全な 64 文字で衝突回避）

### 3. オプション除外の理由

```
--region ap-northeast-1 を明示
--region なし（プロファイルから解決）
↓
どちらも同じリージョンなら同じキャッシュを使うべき
↓
ハッシュ生成時に --region を除外
```

この設計により、ユーザーがどのようにコマンドを実行しても、**実質的に同じクエリなら同じキャッシュが使われる**ようになっています。

---

## パフォーマンス比較

### 修正前

```
aws_cached rds describe-db-clusters
  - リージョン解決: 200ms（設定ファイル全体を読み込み）
  - AWS API呼び出し: 2000ms
  - 合計: 2200ms
```

### 修正後（初回）

```
aws_cached rds describe-db-clusters
  - リージョン解決: 12ms（awkで高速検索）
  - AWS API呼び出し: 2000ms
  - 合計: 2012ms

改善: 188ms短縮
```

### 修正後（2 回目、ファイルキャッシュヒット）

```
aws_cached rds describe-db-clusters
  - リージョン解決: 12ms
  - キャッシュ読み込み: 30ms
  - 合計: 42ms

改善: 元の2200msから約52倍高速化
```

---

## まとめ

AWS CLI Cache は、以下の仕組みで AWS CLI コマンドを高速化します：

1. **パラメータ抽出**: コマンドから必要な情報を抽出
2. **ハッシュ生成**: `--region`等を除外してハッシュ化
3. **キャッシュパス構築**: 6 層のディレクトリ構造
4. **キャッシュヒット判定**: ファイル検索と TTL チェック
5. **リージョン解決**: 優先順位に基づく高速解決

この設計により、オプション指定方法に関わらず、実質的に同じクエリなら同じキャッシュが使われ、大幅な性能改善が実現されています。
