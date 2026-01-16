# AWS CLI Cache v4.2.0 - bash/zsh 完全互換性とドキュメント整理

## 🎉 主な変更

### ✨ bash/zsh 完全互換性

v4.2.0 では、bash と zsh の両方で完全に動作するように実装を改善しました。

**実装内容**:

- すべてのモジュールに `_get_script_path()` ヘルパー関数を追加
- bash: `BASH_SOURCE` を使用したスクリプトパス解決
- zsh: `${(%):-%x}` と `ZSH_EVAL_CONTEXT` を使用した互換実装
- source 検出の実装 (bash/zsh それぞれに対応)

**効果**:

- `.bashrc` / `.zshrc` から `source` で読み込み可能
- 両シェルで構文チェック合格
- 全ユニットテスト合格 (17/17)

### 📚 ドキュメント整理

README.md と USER_GUIDE.md の役割を明確化し、重複を削減しました。

**README.md**:

- クイックリファレンスとして簡潔化（約 200 行削減）
- 初めてのユーザー向けの概要とクイックスタート

**USER_GUIDE.md**:

- 詳細ガイドとして完全な情報を提供
- 実用ユーザー向けの詳細な使用方法とベストプラクティス

### 📝 新規ドキュメント

- **SHELL_COMPATIBILITY.md**: シェル互換性の詳細説明
- **verify_compatibility.sh**: 両シェルでの動作検証スクリプト

## 🔧 互換性

- **Shell**: bash 4.0+ | zsh 5.0+
- **OS**: macOS (BSD) | Linux (GNU)
- **AWS CLI**: v1.x | v2.x

## 📦 インストール

### bash ユーザー

```bash
echo 'source /path/to/aws_cache.sh' >> ~/.bashrc
source ~/.bashrc
```

### zsh ユーザー（macOS デフォルト）

```zsh
echo 'source /path/to/aws_cache.sh' >> ~/.zshrc
source ~/.zshrc
```

## 🧪 テスト

```bash
# 構文チェック
bash -n aws_cache.sh  # ✓
zsh -n aws_cache.sh   # ✓

# ユニットテスト
./tests/unit/run_unit_tests.sh  # 17/17 合格

# 互換性検証
./verify_compatibility.sh  # ✓
```

## 📖 ドキュメント

- **README.md**: クイックスタートと概要
- **USER_GUIDE.md**: 詳細な使用方法
- **SPECIFICATION.md**: 技術仕様
- **SHELL_COMPATIBILITY.md**: シェル互換性の詳細
- **CHANGELOG.md**: 変更履歴

## 🔗 リンク

- [リポジトリ](https://github.com/hacker65536/aws-cli-cache)
- [ドキュメント](https://github.com/hacker65536/aws-cli-cache/blob/main/README.md)
- [変更履歴](https://github.com/hacker65536/aws-cli-cache/blob/main/CHANGELOG.md)

## 👥 貢献者

- Kiro AI Assistant

---

**リリース日**: 2026 年 1 月 16 日  
**バージョン**: 4.2.0
