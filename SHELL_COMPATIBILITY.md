# Shell Compatibility Guide

AWS CLI Cache は bash と zsh の両方で動作するように設計されています。

## サポート対象

### シェル

- ✅ **Bash 4.0+**: 完全対応・推奨
- ✅ **Zsh 5.0+**: 完全対応・macOS デフォルトシェル

### プラットフォーム

- ✅ **macOS** (BSD): bash/zsh 両対応
- ✅ **Linux** (GNU): bash/zsh 両対応
- ⚠️ **Windows WSL**: bash/zsh で動作想定（未テスト）

## 使用方法

### Bash ユーザー

```bash
# .bashrc に追加
echo 'source /path/to/aws_cache.sh' >> ~/.bashrc
source ~/.bashrc

# 使用
aws_cached rds describe-db-clusters
```

### Zsh ユーザー（macOS デフォルト）

```zsh
# .zshrc に追加
echo 'source /path/to/aws_cache.sh' >> ~/.zshrc
source ~/.zshrc

# 使用
aws_cached rds describe-db-clusters
```

## 技術的な実装

### スクリプトパス解決

bash と zsh でスクリプトパスの取得方法が異なるため、互換関数を実装：

```bash
_get_script_path() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        echo "${(%):-%x}"
    elif [ -n "${BASH_SOURCE[0]:-}" ]; then
        echo "${BASH_SOURCE[0]}"
    else
        echo "${0}"
    fi
}
```

### Source 判定

スクリプトが直接実行されたか、source されたかの判定：

```bash
# Bash: BASH_SOURCE[0] と $0 を比較
if [ -n "${BASH_VERSION:-}" ]; then
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        main "$@"
    fi
# Zsh: ZSH_EVAL_CONTEXT を確認
elif [ -n "${ZSH_VERSION:-}" ]; then
    if [[ "${ZSH_EVAL_CONTEXT:-}" == "toplevel" ]]; then
        main "$@"
    fi
fi
```

### POSIX 準拠

GNU 固有機能を避け、macOS/Linux 両対応：

- ❌ `date +%s%N` (macOS 非対応)
- ❌ `xargs -r` (macOS 非対応)
- ❌ `find -printf` (macOS 非対応)
- ✅ `stat` は `$OSTYPE` で分岐

詳細は `.kiro/steering/platform-compatibility.md` を参照。

## テスト

### 互換性テスト

```bash
# 検証スクリプトを実行
./verify_compatibility.sh
```

### 期待される出力

```
=== AWS CLI Cache - Shell Compatibility Verification ===

Test 1: Bash syntax check
✓ All files pass bash syntax check

Test 2: Zsh syntax check
✓ All files pass zsh syntax check

Test 3: Bash source and function availability
✓ Bash: aws_cached function available

Test 4: Zsh source and function availability
✓ Zsh: aws_cached function available

Test 5: Running unit tests
✓ All unit tests passed

=========================================
✓ All compatibility tests passed!
=========================================

Supported shells:
  - bash 4.0+
  - zsh 5.0+

Supported platforms:
  - macOS (BSD)
  - Linux (GNU)
```

## トラブルシューティング

### 関数が見つからない

```bash
# 確認方法
type aws_cached

# Bash の場合
aws_cached is a function

# Zsh の場合
aws_cached is a shell function from /path/to/lib/core.sh
```

### シェルバージョン確認

```bash
# Bash
echo $BASH_VERSION

# Zsh
echo $ZSH_VERSION
```

### 構文エラー

```bash
# Bash で構文チェック
bash -n aws_cache.sh

# Zsh で構文チェック
zsh -n aws_cache.sh
```

## 制限事項

### 非対応シェル

- **Dash**: Bash/Zsh 固有機能を使用しているため非対応
- **Bash 3.2**: 連想配列が使えないため一部機能制限

### 既知の問題

現時点で既知の互換性問題はありません。

## 参考資料

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Bash Reference Manual](https://www.gnu.org/software/bash/manual/)
- [Zsh Documentation](https://zsh.sourceforge.io/Doc/)
- [POSIX Shell Command Language](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html)

---

**最終更新**: 2026 年 1 月 16 日  
**バージョン**: 4.1.1
