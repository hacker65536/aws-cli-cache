# AWS CLI Cache - アーキテクチャドキュメント

## 概要

このドキュメントでは、AWS CLI Cacheの内部アーキテクチャ、データフロー、コンポーネント構成をMermaid図を使用して説明します。

---

## システムアーキテクチャ

### 全体構成

```mermaid
graph TB
    subgraph "User Layer"
        User[ユーザー]
        CLI[AWS CLI Command]
    end
    
    subgraph "Cache Layer"
        Main[aws_cached Function]
        Parser[Parameter Parser]
        Checker[Cache Checker]
        Manager[Cache Manager]
    end
    
    subgraph "Storage Layer"
        FS[File System]
        Cache[(Cache Files)]
        Stats[(Statistics)]
    end
    
    subgraph "AWS Layer"
        AWS[AWS API]
    end
    
    User -->|実行| CLI
    CLI -->|呼び出し| Main
    Main -->|パース| Parser
    Parser -->|判定| Checker
    Checker -->|Hit| Manager
    Checker -->|Miss| AWS
    AWS -->|結果| Manager
    Manager -->|保存/読込| FS
    FS -->|管理| Cache
    FS -->|記録| Stats
    Manager -->|結果| User
```

---

## データフロー

### キャッシュヒット時のフロー

```mermaid
sequenceDiagram
    participant User
    participant aws_cached
    participant extract_*
    participant is_cacheable
    participant find_valid_cache_file
    participant read_cache
    participant FileSystem
    
    User->>aws_cached: aws_cached rds describe-db-clusters
    aws_cached->>extract_*: パラメータ抽出
    extract_*-->>aws_cached: profile, service, region, action, etc.
    
    aws_cached->>is_cacheable: キャッシュ可否判定
    is_cacheable-->>aws_cached: true (キャッシュ可能)
    
    aws_cached->>find_valid_cache_file: キャッシュ検索
    find_valid_cache_file->>FileSystem: ファイル検索
    FileSystem-->>find_valid_cache_file: cache_file
    find_valid_cache_file-->>aws_cached: cache_file (有効)
    
    aws_cached->>read_cache: キャッシュ読み込み
    read_cache->>FileSystem: ファイル読み込み
    FileSystem-->>read_cache: データ
    read_cache-->>aws_cached: キャッシュデータ
    
    aws_cached-->>User: 結果（高速）
```

### キャッシュミス時のフロー

```mermaid
sequenceDiagram
    participant User
    participant aws_cached
    participant extract_*
    participant is_cacheable
    participant find_valid_cache_file
    participant AWS_CLI
    participant check_cache_limits
    participant write_cache
    participant FileSystem
    
    User->>aws_cached: aws_cached ec2 describe-instances
    aws_cached->>extract_*: パラメータ抽出
    extract_*-->>aws_cached: profile, service, region, action, etc.
    
    aws_cached->>is_cacheable: キャッシュ可否判定
    is_cacheable-->>aws_cached: true (キャッシュ可能)
    
    aws_cached->>find_valid_cache_file: キャッシュ検索
    find_valid_cache_file->>FileSystem: ファイル検索
    FileSystem-->>find_valid_cache_file: なし
    find_valid_cache_file-->>aws_cached: null (キャッシュなし)
    
    aws_cached->>AWS_CLI: AWS API実行
    AWS_CLI-->>aws_cached: 結果
    
    aws_cached->>check_cache_limits: サイズ制限チェック
    check_cache_limits->>FileSystem: LRU削除（必要時）
    check_cache_limits-->>aws_cached: OK
    
    aws_cached->>write_cache: キャッシュ保存
    write_cache->>FileSystem: アトミック書き込み
    FileSystem-->>write_cache: 完了
    write_cache-->>aws_cached: 完了
    
    aws_cached-->>User: 結果
```

---

## コンポーネント構成

### 主要コンポーネント

```mermaid
graph LR
    subgraph "Entry Point"
        A[aws_cached]
    end
    
    subgraph "Parameter Extraction"
        B1[extract_profile]
        B2[extract_service]
        B3[extract_region]
        B4[extract_action]
        B5[generate_params_hash]
        B6[extract_format]
    end
    
    subgraph "Cache Logic"
        C1[is_cacheable]
        C2[find_valid_cache_file]
        C3[is_cache_valid]
        C4[get_cache_file]
    end
    
    subgraph "Cache I/O"
        D1[read_cache]
        D2[write_cache]
        D3[check_cache_limits]
    end
    
    subgraph "Management"
        E1[clear_cache]
        E2[clean_expired_cache]
        E3[cache_stats]
        E4[show_cache_metrics]
    end
    
    A --> B1 & B2 & B3 & B4 & B5 & B6
    A --> C1 & C2
    C2 --> C3
    A --> D1 & D2
    D2 --> D3
    A -.管理.- E1 & E2 & E3 & E4
```

---

## キャッシュディレクトリ構造

### 階層構造

```mermaid
graph TD
    Root[CACHE_DIR<br/>~/.cache/aws-cli]
    
    Root --> P1[Profile 1<br/>my-profile]
    Root --> P2[Profile 2<br/>production]
    
    P1 --> S1[Service<br/>rds]
    P1 --> S2[Service<br/>ec2]
    
    S1 --> R1[Region<br/>us-east-1]
    S1 --> R2[Region<br/>ap-northeast-1]
    
    R1 --> A1[Action<br/>describe-db-clusters]
    R1 --> A2[Action<br/>describe-db-instances]
    
    A1 --> H1[Params Hash<br/>a1b2c3d4e5f6g7h8]
    
    H1 --> F1[Format<br/>json]
    H1 --> F2[Format<br/>text]
    
    F1 --> C1[Cache File<br/>hash_3600_1234567890_12345.cache]
    F1 --> C2[Cache File<br/>hash_3600_1234567891_12346.cache]
    
    style Root fill:#e1f5ff
    style P1 fill:#fff4e1
    style S1 fill:#ffe1f5
    style R1 fill:#e1ffe1
    style A1 fill:#f5e1ff
    style H1 fill:#ffe1e1
    style F1 fill:#e1e1ff
    style C1 fill:#f0f0f0
```

---

## 状態遷移図

### キャッシュファイルのライフサイクル

```mermaid
stateDiagram-v2
    [*] --> NotExists: 初期状態
    
    NotExists --> Creating: AWS CLI実行（キャッシュミス）
    Creating --> Valid: 書き込み完了
    
    Valid --> Valid: 読み込み（TTL内）
    Valid --> Expired: TTL経過
    Valid --> Invalid: 整合性チェック失敗
    
    Expired --> Deleted: clean実行
    Invalid --> Deleted: 自動削除
    Valid --> Deleted: clear実行
    Valid --> Deleted: LRU削除
    
    Deleted --> [*]
    
    note right of Valid
        TTL内は有効
        アクセス時刻を更新
    end note
    
    note right of Expired
        期限切れだが
        ファイルは残存
    end note
```

---

## 並行実行の仕組み

### アトミック書き込み

```mermaid
sequenceDiagram
    participant P1 as Process 1
    participant P2 as Process 2
    participant P3 as Process 3
    participant FS as File System
    
    par 並行実行
        P1->>FS: 一時ファイル作成<br/>file.tmp.1001
        P2->>FS: 一時ファイル作成<br/>file.tmp.1002
        P3->>FS: 一時ファイル作成<br/>file.tmp.1003
    end
    
    par データ書き込み
        P1->>FS: データ書き込み
        P2->>FS: データ書き込み
        P3->>FS: データ書き込み
    end
    
    par アトミック移動
        P1->>FS: mv file.tmp.1001<br/>→ hash_ttl_ts_1001.cache
        P2->>FS: mv file.tmp.1002<br/>→ hash_ttl_ts_1002.cache
        P3->>FS: mv file.tmp.1003<br/>→ hash_ttl_ts_1003.cache
    end
    
    Note over P1,FS: 各プロセスが独立した<br/>キャッシュファイルを作成<br/>（PIDで区別）
```

---

## LRU削除の仕組み

### サイズ制限とLRU削除

```mermaid
flowchart TD
    Start([キャッシュ書き込み開始])
    
    Start --> CheckFiles{ファイル数<br/>≥ MAX_FILES?}
    CheckFiles -->|Yes| LRUFiles[古いファイルから削除<br/>アクセス時刻順]
    CheckFiles -->|No| CheckSize
    
    LRUFiles --> CheckSize{サイズ<br/>≥ MAX_SIZE?}
    
    CheckSize -->|Yes| LRUSize[80%まで削減<br/>アクセス時刻順]
    CheckSize -->|No| Write
    
    LRUSize --> Write[キャッシュ書き込み]
    Write --> End([完了])
    
    style Start fill:#e1f5ff
    style End fill:#e1ffe1
    style CheckFiles fill:#fff4e1
    style CheckSize fill:#fff4e1
    style LRUFiles fill:#ffe1e1
    style LRUSize fill:#ffe1e1
    style Write fill:#e1ffe1
```

---

## キャッシュ判定フロー

### is_cacheable関数の処理

```mermaid
flowchart TD
    Start([コマンド実行])
    
    Start --> Extract[サービス・アクション抽出]
    Extract --> LoadRules[除外ルール読み込み]
    
    LoadRules --> CheckCache{キャッシュ済み?}
    CheckCache -->|Yes| UseCache[キャッシュから取得]
    CheckCache -->|No| LoadFile[ファイルから読み込み]
    
    LoadFile --> Cache[ルールをキャッシュ]
    Cache --> UseCache
    
    UseCache --> Loop{各ルールを<br/>チェック}
    
    Loop -->|service:action| Match1{完全一致?}
    Match1 -->|Yes| Exclude[キャッシュしない]
    Match1 -->|No| Next1
    
    Next1 -->|service:*| Match2{サービス一致?}
    Match2 -->|Yes| Exclude
    Match2 -->|No| Next2
    
    Next2 -->|*:action| Match3{アクション一致?}
    Match3 -->|Yes| Exclude
    Match3 -->|No| Next3
    
    Next3 --> Loop
    
    Loop -->|全てチェック完了| Allow[キャッシュする]
    
    Exclude --> End1([return 1])
    Allow --> End2([return 0])
    
    style Start fill:#e1f5ff
    style Exclude fill:#ffe1e1
    style Allow fill:#e1ffe1
    style End1 fill:#ffe1e1
    style End2 fill:#e1ffe1
```

---

## 統計情報の記録

### メトリクス収集フロー

```mermaid
sequenceDiagram
    participant User
    participant aws_cached
    participant Cache
    participant Stats[.stats File]
    participant Metrics[show_cache_metrics]
    
    Note over User,Metrics: AWS_CACHE_STATS=true の場合
    
    User->>aws_cached: コマンド実行
    
    alt キャッシュヒット
        aws_cached->>Cache: キャッシュ読み込み
        Cache-->>aws_cached: データ
        aws_cached->>Stats: timestamp,hit
    else キャッシュミス
        aws_cached->>Cache: AWS API実行
        Cache-->>aws_cached: データ
        aws_cached->>Stats: timestamp,miss
    end
    
    aws_cached-->>User: 結果
    
    Note over User,Metrics: メトリクス表示時
    
    User->>Metrics: ./aws_cache.sh metrics
    Metrics->>Stats: 統計データ読み込み
    Stats-->>Metrics: timestamp,hit/miss
    Metrics->>Metrics: 集計・計算
    Metrics-->>User: ヒット率表示
```

---

## エラーハンドリング

### エラー処理フロー

```mermaid
flowchart TD
    Start([AWS CLI実行])
    
    Start --> Exec[コマンド実行]
    Exec --> Capture[stdout/stderr分離]
    
    Capture --> Check{終了コード}
    
    Check -->|0 成功| SaveCache[キャッシュ保存]
    SaveCache --> CheckWrite{書き込み成功?}
    CheckWrite -->|Yes| Output1[結果出力]
    CheckWrite -->|No| Warn[警告出力]
    Warn --> Output1
    Output1 --> Success([return 0])
    
    Check -->|非0 失敗| ShowError[エラー表示]
    ShowError --> Output2[stderr出力]
    Output2 --> Fail([return exit_code])
    
    style Start fill:#e1f5ff
    style Success fill:#e1ffe1
    style Fail fill:#ffe1e1
    style ShowError fill:#ffe1e1
    style Warn fill:#fff4e1
```

---

## 管理コマンドの構成

### コマンド処理フロー

```mermaid
graph TD
    Main[main Function]
    
    Main -->|clear| Clear[clear_cache]
    Main -->|clean| Clean[clean_expired_cache]
    Main -->|stats| Stats[cache_stats]
    Main -->|metrics| Metrics[show_cache_metrics]
    Main -->|tree| Tree[ディレクトリ構造表示]
    Main -->|excludes| Excludes[除外ルール表示]
    Main -->|add-exclude| Add[除外ルール追加]
    Main -->|remove-exclude| Remove[除外ルール削除]
    Main -->|test| Test[動作テスト]
    Main -->|help| Help[ヘルプ表示]
    
    Clear --> FS1[ファイルシステム操作]
    Clean --> FS2[期限切れファイル削除]
    Stats --> FS3[統計情報収集]
    Metrics --> FS4[メトリクス計算]
    Tree --> FS5[ディレクトリ走査]
    Excludes --> Config1[設定ファイル読み込み]
    Add --> Config2[設定ファイル追記]
    Remove --> Config3[設定ファイル編集]
    Test --> TestExec[テスト実行]
    
    style Main fill:#e1f5ff
    style Clear fill:#ffe1e1
    style Clean fill:#fff4e1
    style Stats fill:#e1ffe1
    style Metrics fill:#e1ffe1
```

---

## パフォーマンス最適化

### 最適化ポイント

```mermaid
mindmap
  root((パフォーマンス<br/>最適化))
    キャッシュ戦略
      階層化構造
        プロファイル別
        サービス別
        リージョン別
      TTL管理
        柔軟な設定
        ファイル名に埋め込み
      LRU削除
        アクセス時刻ベース
        自動削除
    並行実行
      アトミック書き込み
        一時ファイル使用
        mvコマンド
      PIDベース命名
        衝突回避
        独立実行
    メモリ最適化
      除外ルールキャッシュ
        初回読み込み
        メモリ保持
      パラメータ抽出
        効率的なパース
        最小限の処理
    I/O最適化
      ファイル検索
        階層的検索
        早期終了
      バッチ削除
        LRU一括処理
        効率的な削除
```

---

## セキュリティモデル

### セキュリティレイヤー

```mermaid
graph TB
    subgraph "入力検証"
        Input[ユーザー入力]
        Validate[パラメータ検証]
        Quote[クォート処理]
    end
    
    subgraph "ファイルシステム"
        Path[パストラバーサル対策]
        Perm[ファイル権限]
        Atomic[アトミック操作]
    end
    
    subgraph "データ整合性"
        Hash[SHA256ハッシュ]
        Verify[整合性検証]
        Delete[自動削除]
    end
    
    subgraph "環境変数"
        Env[環境変数管理]
        NoHardcode[ハードコード禁止]
    end
    
    Input --> Validate
    Validate --> Quote
    Quote --> Path
    Path --> Perm
    Perm --> Atomic
    Atomic --> Hash
    Hash --> Verify
    Verify --> Delete
    
    Env --> NoHardcode
    NoHardcode --> Validate
    
    style Input fill:#e1f5ff
    style Validate fill:#fff4e1
    style Path fill:#ffe1e1
    style Hash fill:#e1ffe1
    style Env fill:#f5e1ff
```

---

## まとめ

このアーキテクチャドキュメントでは、AWS CLI Cacheの内部構造を視覚的に説明しました。

### 主要な設計原則

1. **階層化**: 6層の論理的な構造
2. **並行性**: アトミック操作とPIDベース命名
3. **効率性**: LRU削除とメモリキャッシュ
4. **安全性**: 整合性検証とエラーハンドリング
5. **拡張性**: プラグイン可能な除外ルール

---

**作成者**: Kiro AI Assistant  
**作成日**: 2025年11月19日  
**バージョン**: 3.0.0
