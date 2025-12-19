---
inclusion: always
---

# AWS CLI Cache 仕様

## 環境変数

| 変数                       | デフォルト                        | 説明                   |
| -------------------------- | --------------------------------- | ---------------------- |
| `AWS_CACHE_DIR`            | `~/.cache/aws-cli`                | キャッシュディレクトリ |
| `AWS_CACHE_TTL`            | `3600`                            | デフォルト TTL（秒）   |
| `AWS_CACHE_MAX_SIZE`       | `1073741824`                      | 最大サイズ（1GB）      |
| `AWS_CACHE_MAX_FILES`      | `10000`                           | 最大ファイル数         |
| `AWS_CACHE_VERIFY`         | `false`                           | 整合性チェック         |
| `AWS_CACHE_STATS`          | `false`                           | 統計記録               |
| `AWS_CACHE_EXCLUDE_CONFIG` | `~/.config/aws-cli/cache-exclude` | 除外設定               |

## コマンドライン

### aws_cached オプション

```
--cache-ttl <seconds>  個別TTL設定
--force-refresh        キャッシュ無視
--no-cache            キャッシュ不使用
--verbose             詳細ログ
```

### 管理コマンド

```
clear [target]        キャッシュクリア
clean                 期限切れ削除
stats [target]        統計表示
metrics               メトリクス表示
excludes              除外ルール表示
add-exclude <rule>    除外ルール追加
remove-exclude <rule> 除外ルール削除
tree                  構造表示
test                  動作テスト
```

## キャッシュ構造

### ディレクトリ（6 層）

```
{profile}/{service}/{region}/{action}/{params_hash}/{format}/
```

### ファイル名

```
{hash}_{ttl}_{pid}.cache
```

## 除外ルール形式

```
service:action    # 完全一致
service:*         # サービス全体
*:action          # アクション全体
```

## パフォーマンス基準

| 状態             | 目標         |
| ---------------- | ------------ |
| キャッシュヒット | 元の 45%以下 |
| キャッシュミス   | 元の 51%以下 |
| 高速化率         | 2.2 倍以上   |

## 互換性

- OS: macOS, Linux
- Shell: bash 4.0+
- AWS CLI: v1.x, v2.x
