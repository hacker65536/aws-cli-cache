# v4.1.1

## 🐛 Bug Fixes

### キャッシュ共有の問題を修正

`--region` オプションの有無によって異なるキャッシュファイルが生成され、キャッシュが共有されない問題を修正しました。

**問題:**

```bash
# これらのコマンドは同じリージョンに対するクエリだが、異なるキャッシュが作られていた
aws_cached rds describe-db-clusters --region ap-northeast-1
aws_cached rds describe-db-clusters  # プロファイルから ap-northeast-1 を解決
```

**修正内容:**

- `generate_cache_key()` 関数で `--region`, `--profile`, `--output` オプションを除外してからハッシュ化
- これにより、オプション指定方法に関わらず、実質的に同じクエリなら同じキャッシュが使われるようになりました

## ⚡ Performance Improvements

### リージョン解決の高速化

プロファイルからリージョンを解決する処理を最適化しました。

- `get_profile_region()` 関数を `awk` を使った高速検索に変更
- **200ms → 12ms** (約 16 倍高速化)
- 大きな設定ファイル（4893 行）でも高速に動作

## 📚 Documentation

### キャッシュ機構の詳細ドキュメントを追加

`docs/CACHE_MECHANISM.md` を追加し、以下の内容を詳しく説明:

- パラメータ抽出からキャッシュヒット判定までの全体フロー
- ハッシュ生成の仕組み
- リージョン解決の優先順位
- ファイルキャッシュとメモリキャッシュの違い
- 具体的な使用例とパフォーマンス比較

## 🔧 Changes

- `lib/hash.sh`: `generate_cache_key()` の修正
- `lib/profile_region.sh`: `get_profile_region()` の最適化
- `tests/unit/test_hash.sh`: テストケースの更新

## 📊 Performance Impact

```
修正前:
  aws_cached rds describe-db-clusters
  - リージョン解決: 200ms
  - AWS API: 2000ms
  - 合計: 2200ms

修正後（初回）:
  - リージョン解決: 12ms
  - AWS API: 2000ms
  - 合計: 2012ms

修正後（2回目、キャッシュヒット）:
  - リージョン解決: 12ms
  - キャッシュ読み込み: 30ms
  - 合計: 42ms (元の約52倍高速)
```
