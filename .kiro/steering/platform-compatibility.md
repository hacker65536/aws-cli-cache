---
inclusion: always
---

# プラットフォーム互換性ガイド

macOS (BSD) と Linux (GNU) でコマンドの動作が異なる。このプロジェクトでは標準の POSIX コマンドを使用し、GNU 固有機能は避ける。

## コマンド別の違いと対処法

### date

| 機能               | BSD (macOS)       | GNU (Linux)        | 互換性のある方法 |
| ------------------ | ----------------- | ------------------ | ---------------- |
| エポック秒取得     | `date +%s`        | `date +%s`         | ✅ 共通          |
| エポック秒から変換 | `date -r <epoch>` | `date -d @<epoch>` | ❌ 異なる        |
| ナノ秒             | 未サポート        | `date +%s%N`       | ❌ 使用禁止      |

```bash
# 推奨: エポック秒のみ使用
current_time=$(date +%s)

# 避ける: ナノ秒（macOSで動作しない）
# time_ns=$(date +%s%N)
```

### xargs

| 機能             | BSD (macOS) | GNU (Linux) | 互換性のある方法 |
| ---------------- | ----------- | ----------- | ---------------- |
| 空入力時スキップ | 未サポート  | `-r`        | ❌ 異なる        |
| NULL 区切り      | `-0`        | `-0`        | ✅ 共通          |

```bash
# 避ける: -r オプション
# find ... | xargs -r rm -f

# 推奨: whileループで代替
while IFS= read -r -d '' file; do
    [[ -f "${file}" ]] && rm -f "${file}"
done < <(find ... -print0)

# または: 条件付き実行
files=$(find ... -type f)
[[ -n "${files}" ]] && echo "${files}" | xargs rm -f
```

### find

| 機能      | BSD (macOS) | GNU (Linux) | 互換性のある方法 |
| --------- | ----------- | ----------- | ---------------- |
| 基本検索  | ✅          | ✅          | ✅ 共通          |
| `-printf` | 未サポート  | サポート    | ❌ 使用禁止      |
| `-print0` | ✅          | ✅          | ✅ 共通          |

```bash
# 避ける: -printf（macOSで動作しない）
# find "$dir" -type f -printf '%T@ %p\n'

# 推奨: ls と組み合わせ
find "$dir" -type f -print0 | xargs -0 ls -lt

# または: stat を使用（下記参照）
```

### sed

| 機能             | BSD (macOS)          | GNU (Linux) | 互換性のある方法 |
| ---------------- | -------------------- | ----------- | ---------------- |
| インプレース編集 | `-i ''` (空文字必須) | `-i`        | ❌ 異なる        |
| 基本置換         | ✅                   | ✅          | ✅ 共通          |

```bash
# 避ける: インプレース編集（OS依存）
# sed -i 's/old/new/' file      # GNU
# sed -i '' 's/old/new/' file   # BSD

# 推奨: 一時ファイル経由
sed 's/old/new/' file > file.tmp && mv file.tmp file
```

### stat

| 機能         | BSD (macOS) | GNU (Linux) | 互換性のある方法  |
| ------------ | ----------- | ----------- | ----------------- |
| アクセス時刻 | `-f '%a'`   | `-c '%X'`   | ⚠️ OS 検出で分岐  |
| 変更時刻     | `-f '%m'`   | `-c '%Y'`   | ⚠️ OS 検出で分岐  |
| サイズ       | `-f '%z'`   | `-c '%s'`   | ❌ `wc -c` を使用 |

```bash
# 許容: $OSTYPE による分岐（変更時刻取得が必要な場合）
if [[ "$OSTYPE" == "darwin"* ]]; then
    file_mtime=$(stat -f %m "$file" 2>/dev/null)
else
    file_mtime=$(stat -c %Y "$file" 2>/dev/null)
fi

# 推奨: 可能であれば ls -l からパース、または find の -newer
```

### du

| 機能       | BSD (macOS) | GNU (Linux) | 互換性のある方法 |
| ---------- | ----------- | ----------- | ---------------- |
| KB 単位    | `-sk`       | `-sk`       | ✅ 共通          |
| バイト単位 | 未サポート  | `-sb`       | ❌ 使用禁止      |

```bash
# 推奨: KB単位を使用
cache_size_kb=$(du -sk "$dir" | cut -f1)

# 避ける: バイト単位（macOSで動作しない）
# cache_size=$(du -sb "$dir" | cut -f1)
```

## 推奨パターン

### ファイルのアクセス時刻順ソート

```bash
# 推奨: ls -tu を使用
find "$dir" -type f -name "*.cache" | xargs ls -tu

# 避ける: find -printf + sort
# find "$dir" -type f -printf '%A@ %p\n' | sort -n
```

### 空入力の安全な処理

```bash
# 推奨: whileループ
while IFS= read -r -d '' file; do
    [[ -f "${file}" ]] && rm -f "${file}"
done < <(find "$dir" -type f -name "*.cache" -print0)

# 避ける: xargs -r
# find ... | xargs -r rm -f
```

### ファイルサイズ取得

```bash
# 推奨: wc -c を使用
file_size=$(wc -c < "$file")

# または: ls -l からパース
file_size=$(ls -l "$file" | awk '{print $5}')
```

## GNU coreutils がインストールされている場合

macOS で Homebrew から GNU coreutils をインストールしている場合、`g`プレフィックス付きコマンドが利用可能:

- `gdate`, `gfind`, `gxargs`, `gsed`, `gstat`, `gdu`, `greadlink`

ただし、**このプロジェクトでは GNU コマンドに依存しない**。すべての環境で動作する標準的な方法を使用する。

## チェックリスト

新しいコードを書く際の確認事項:

- [ ] `date +%s%N` を使用していないか
- [ ] `xargs -r` を使用していないか
- [ ] `find -printf` を使用していないか
- [ ] `sed -i` を使用していないか（一時ファイル経由に変更）
- [ ] `stat` を使用する場合は `$OSTYPE` で分岐しているか
- [ ] `du -sb` を使用していないか（`-sk`を使用）
