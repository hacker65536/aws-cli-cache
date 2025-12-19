---
inclusion: always
---

# アーキテクチャ原則

## 並行実行対応

### アトミック操作（必須パターン）

```bash
local temp_file="${cache_file}.tmp.$$"
echo "${data}" > "${temp_file}"
mv "${temp_file}" "${cache_file}"
```

### PID ベース命名

- ファイル名に`$$`（プロセス ID）を含める
- 複数プロセス同時実行時の衝突回避

## パフォーマンス最適化

### メモリキャッシュ

- 除外ルールは初回読み込み後メモリ保持
- ファイル I/O 削減

### LRU 削除

- アクセス時刻ベースの自動削除
- サイズ制限: 80%まで削減

## セキュリティ

### 整合性検証

```bash
if [[ "${AWS_CACHE_VERIFY:-false}" == true ]]; then
    shasum -a 256 "${temp_file}" | cut -d' ' -f1 > "${temp_file}.sha256"
fi
```

### エラーハンドリング

```bash
local temp_stdout=$(mktemp)
local temp_stderr=$(mktemp)
trap 'rm -f "${temp_stdout}" "${temp_stderr}"' EXIT
aws "$@" > "${temp_stdout}" 2> "${temp_stderr}"
```

## 互換性

### 後方互換性

- 既存 API の変更禁止
- 新機能はオプトイン方式

### クロスプラットフォーム

- macOS/Linux 両対応
- GNU 固有コマンド回避
- 詳細は `platform-compatibility.md` を参照
