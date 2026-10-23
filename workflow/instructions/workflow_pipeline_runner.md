# workflow_pipeline_runner

## 1. 責務（Single Responsibility）
リサーチからスプレッドシート反映までの一連の工程モジュール（`research_*`, `eval_*`, `portfolio_*`, `guard_*`, `sheet_*`）を順序立てて連携させ、パイプラインとして安全かつ確実に実行・制御する。

## 2. 入力（Input）
- `SeedKeywords`: 探索の起点となるキーワード一覧（配列）
- `DryRun`: スプレッドシートへの書き込みを行わずにシミュレーションのみ行うフラグ（デフォルト: False）
- `MaxKeywords`: 今回の実行で検証する最大キーワード数

## 3. 出力（Output）
- `Status`: パイプライン実行結果（Completed, LimitReached, Failed）
- `ProcessedCount`: 処理した候補キーワード数
- `DiscoveredHits`: 新規発見された当たりKW数
- `CommittedCount`: スプレッドシートへ反映されたKW数
- `ShelvedCount`: 一時退避ストックへ回されたKW数
- `SheetRatio`: 反映後のスプレッドシート全体比率
- `ExecutionSummary`: 実行サマリーログ

## 4. 実行フロー（パイプライン順序）
```text
1. [sheet_data_reader]       現行シートデータと登録済みKWの取得
2. [research_seed_suggest]   候補KWのクレンジング・重複除外
3. [research_volume_verifier] 月間検索ボリュームの実測・1,900未満の除外
4. [research_serp_fetcher]   上位10位SERPデータの取得・解析
5. [eval_star_calculator]    厳格DA 1〜9カウントと星数（☆1〜☆5）判定
6. [eval_site_extractor]     合格サイトの行データ成形
7. [portfolio_ratio_balancer] 全体黄金比率（50:25:25）に基づく投入枠配分
8. [guard_normal_state]      スプシ書き込み前ガードレール判定
9. [sheet_atomic_writer]     Google Sheets APIアトミック書き込み
10. [guard_quota_monitor]    APIエラー監視と枯渇エビデンス記録
```
