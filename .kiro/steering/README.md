# ステアリングルール

AWS CLI Cache プロジェクトの開発ガイドライン。

## ファイル構成

| ファイル                      | 内容                                             |
| ----------------------------- | ------------------------------------------------ |
| `coding-standards.md`         | Google Shell Style Guide 準拠のコーディング標準  |
| `naming-conventions.md`       | 変数・関数の命名規則                             |
| `architecture-principles.md`  | 並行実行、パフォーマンス、セキュリティの設計原則 |
| `development-guidelines.md`   | テスト、リリース、プライバシーのガイドライン     |
| `aws-cache-specifications.md` | 環境変数、コマンド、キャッシュ構造の技術仕様     |
| `platform-compatibility.md`   | macOS/Linux 間のコマンド互換性ガイド             |

## 適用条件

すべて`inclusion: always`で常時適用。

## 参考

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- プロジェクトドキュメント: `docs/`
- テスト: `tests/`
