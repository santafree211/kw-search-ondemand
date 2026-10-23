# キーワードサーチ工程モジュール索引（WORKFLOW INDEX）

本プロジェクトは、キーワード探索（リサーチからスプレッドシート記入まで）の一連の作業を、**トークン管理**・**指示修正の容易さ**・**ファイル管理の透明性** を最大化するため、**「1工程（1責務）1ファイル」** かつ **`カテゴリー_機能.拡張子`** の命名規則に完全統一したモジュール構成を採用しています。

---

## 1. 命名規則と構成思想

### 命名形式
`[カテゴリー]_[機能名].[拡張子]`

- **カテゴリー一覧**:
  - `research_`: リサーチ・キーワード発掘・APIデータ取得
  - `eval_`: 判定・スコアリング・サイト情報抽出
  - `portfolio_`: 比率計算・在庫配分・枠制御
  - `guard_`: ガードレール・品質検査・API枯渇検知
  - `sheet_`: Google Sheets API認証・データ読み込み・アトミック更新
  - `workflow_`: 各工程を連結するパイプライン統合制御

### ファイル種別と責務の分離
| ディレクトリ | 拡張子 | 役割・用途 |
| :--- | :--- | :--- |
| `workflow/instructions/` | `.md` | **【AI指示修正・トークン管理】** 各工程のプロンプト・判定規則・入出力仕様書。エージェントが必要な工程のみ読み込むことで、コンテキストトークン消費を最小化。 |
| `workflow/scripts/` | `.ps1` | **【即時実行スクリプト】** Windows PowerShell 5.1 ネイティブ対応の実行モジュール。Pure ASCII設計で文字化けゼロ。 |
| `workflow/python/` | `.py` | **【ポータブル実行スクリプト】** Python 3 標準対応の実行モジュール。 |
| `workflow/data/` | `.json` | **【状態・キャッシュ保管】** 実測ボリュームエビデンス（`verified_volume_cache.json`）や比率退避ストック（`shelved_stock.json`）の永続化。 |

---

## 2. 全モジュール一覧と入出力マスタ

| カテゴリー | モジュール名 | 指示書 (.md) | 実行スクリプト (.ps1 / .py) | 責務（何をするか） | 主な入力 | 主な出力 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **sheet** | `sheet_auth_provider` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/sheet_auth_provider.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/sheet_auth_provider.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/sheet_auth_provider.py) | サービスアカウント秘密鍵からOAuth2 JWTアクセストークンを発行 | サービスアカウントJSON | Bearer AccessToken |
| **sheet** | `sheet_data_reader` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/sheet_data_reader.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/sheet_data_reader.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/sheet_data_reader.py) | 『当たりKW』シートの最新全行データを取得・パース | SheetId, SheetName | Rows (2次元配列), SiteCount |
| **research** | `research_seed_suggest` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/research_seed_suggest.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/research_seed_suggest.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/research_seed_suggest.py) | 起点KW・サジェストの正規化、記号除去、既存シート重複除外 | RawKeywords, ExcludeKeywords | CandidateKeywords (配列) |
| **research** | `research_bulk_expand` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/research_bulk_expand.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/research_bulk_expand.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/research_bulk_expand.py) | シードから最大50KW＋ボリュームを1回で一括取得・検証（枠98%節約） | SeedKeywords, MinVolume | EligibleCandidates, Cache自動更新 |
| **research** | `research_domain_extract` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/research_domain_extract.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/research_domain_extract.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/research_domain_extract.py) | 競合個人ブログ（DA 1〜9）の上位KW・ボリュームを1回で一括取得（枠90%節約） | Domain, MinVolume, MaxPos | WinningKeywords, Cache自動更新 |
| **research** | `research_volume_verifier` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/research_volume_verifier.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/research_volume_verifier.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/research_volume_verifier.py) | API実測ボリュームの検証（1,900未満即除外、推測・仮置き絶対禁止） | Keyword, ApiResponse | Passed (bool), SearchVolume, Cache更新 |
| **research** | `research_serp_fetcher` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/research_serp_fetcher.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/research_serp_fetcher.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/research_serp_fetcher.py) | 上位10位オーガニックSERPの抽出・ドメイン正規化 | Keyword, SerpResponse | Top10Organic (配列) |
| **eval** | `eval_weak_competitor_rule` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/eval_weak_competitor_rule.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/eval_weak_competitor_rule.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/eval_weak_competitor_rule.py) | ドメイン/URLが実質DA一桁（弱競合UGC・知恵袋・note等）か判定 | Domain, Url | IsWeakCompetitor (bool), Category, Reason |
| **eval** | `eval_star_calculator` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/eval_star_calculator.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/eval_star_calculator.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/eval_star_calculator.py) | 個人が抜ける席（DA 1〜9ブログ＋弱競合UGC）をカウント、☆判定 | Keyword, Volume, SerpEntries | StarCount, FormattedValue, IsHit, LowDaSites |
| **eval** | `eval_site_extractor` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/eval_site_extractor.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/eval_site_extractor.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/eval_site_extractor.py) | 当たりKWを持つ対象サイトのメタ情報抽出・スプシ行オブジェクト成形 | LowDaSites, OriginKw, WinningKws | SiteRow (Object) |
| **portfolio** | `portfolio_ratio_balancer` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/portfolio_ratio_balancer.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/portfolio_ratio_balancer.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/portfolio_ratio_balancer.py) | シート全体の黄金比率（☆3以上:50%+, ☆2:25%, ☆1:25%）枠配分とストック退避 | CurrentKws, NewKws | CommitKeywords, ShelvedKeywords |
| **guard** | `guard_normal_state` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/guard_normal_state.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/guard_normal_state.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/guard_normal_state.py) | スプシ更新前ゲート（空行ゼロ、該当無しゼロ、★ゼロ、Vol>=1900、比率50:25:25） | SheetRows, VerifiedVolumeMap | Passed (bool), Errors, Ratios |
| **guard** | `guard_quota_monitor` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/guard_quota_monitor.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/guard_quota_monitor.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/guard_quota_monitor.py) | API物理エラー（403/429/タイムアウト）検知、実質コール回数と枯渇エビデンス集計 | ErrorText, CallLogs | IsExhausted (bool), ExhaustionEvidence |
| **sheet** | `sheet_atomic_writer` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/sheet_atomic_writer.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/sheet_atomic_writer.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/sheet_atomic_writer.py) | 事前ガードレール検証 ➔ 範囲クリア ➔ 一括アトミック書き込み | SheetRows, SheetId, SheetName | UpdatedRows, UpdatedCells |
| **workflow** | `workflow_pipeline_runner` | [指示書](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/workflow_pipeline_runner.md) | [.ps1](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/workflow_pipeline_runner.ps1) / [.py](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/python/workflow_pipeline_runner.py) | 全工程を一括連携実行するオーケストレーター | SeedKeywords, DryRun | PipelineSummary |

---

## 3. エージェント専用CLI実行ツール一覧（tools/）

エージェントが日常の探索タスクや検証を行う際、使い捨てスクリプトを一切作らずに1発で実行できるように整備された専用CLIツール群です。すべてのツールはトークン消費を最小化するコンパクトな出力（JSON/サマリー）を返します。

| 実行ファイル (tools/) | 役割・用途 | 実行コマンド例 |
| :--- | :--- | :--- |
| [`tools/sheet_audit_health.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/sheet_audit_health.ps1) | スプレッドシート健全性監査（比率50:25:25、空行ゼロ、★ゼロ、Vol>=1900） | `powershell -File tools\sheet_audit_health.ps1` |
| [`tools/sheet_inspect_rows.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/sheet_inspect_rows.ps1) | スプシの行一覧・当たりKWを1行1サイト形式で確認 | `powershell -File tools\sheet_inspect_rows.ps1 -EndRow 30` |
| [`tools/sheet_get_token.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/sheet_get_token.ps1) | Google API OAuth2アクセストークン取得 | `powershell -File tools\sheet_get_token.ps1` |
| [`tools/sheet_commit_site.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/sheet_commit_site.ps1) | 安全なサイト＋当たりKW登録（黄金比率保護・アトミック更新） | `powershell -File tools\sheet_commit_site.ps1 -SiteJsonPath "site.json"` |
| [`tools/research_verify_volume.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/research_verify_volume.ps1) | 月間ボリューム実測・検証（第6条物理検証・キャッシュ登録） | `powershell -File tools\research_verify_volume.ps1 -Keyword "KW"` |
| [`tools/research_normalize_candidates.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/research_normalize_candidates.ps1) | 候補KWの記号・黒星除去、既存シート重複除外 | `powershell -File tools\research_normalize_candidates.ps1 -RawKeywords @('KW1', 'KW2')` |
| [`tools/research_bulk_expand.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/research_bulk_expand.ps1) | 関連語バルク展開・一括ボリューム検証（トークン98%節約・1枠で最大50件検証） | `powershell -File tools\research_bulk_expand.ps1 -SeedKeywords @('KW')` |
| [`tools/research_domain_extract.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/research_domain_extract.ps1) | 競合ドメイン一括KW・ボリューム抽出（トークン90%節約・1枠で全上位KW取得） | `powershell -File tools\research_domain_extract.ps1 -Domain "example.com"` |
| [`tools/eval_check_weak_competitor.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/eval_check_weak_competitor.ps1) | 弱競合UGC判定（指定ドメイン/URLが知恵袋・note等の実質DA一桁か判定） | `powershell -File tools\eval_check_weak_competitor.ps1 -Domain "note.com"` |
| [`tools/eval_evaluate_serp.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/eval_evaluate_serp.ps1) | SERP上位10件の厳格星数評価（DA 1〜9個人ブログ＋弱競合UGCの席数合算） | `powershell -File tools\eval_evaluate_serp.ps1 -Keyword "KW" -SearchVolume 2400 -SerpJsonPath "serp.json"` |
| [`tools/portfolio_inspect_stock.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/portfolio_inspect_stock.ps1) | 比率・保留中ストック（shelved_stock）の確認・追加可能枠計算 | `powershell -File tools\portfolio_inspect_stock.ps1` |
| [`tools/guard_check_exhaustion.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/guard_check_exhaustion.ps1) | API枯渇・ハードストップ判定・枯渇エビデンス出力 | `powershell -File tools\guard_check_exhaustion.ps1 -ErrorText "エラー内容"` |
| [`tools/workflow_run_pipeline.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/tools/workflow_run_pipeline.ps1) | 自律探索パイプライン実行 | `powershell -File tools\workflow_run_pipeline.ps1 -SeedKeywords @('KW1') -DryRun` |

---

## 4. トークン管理・指示修正の運用手順

### ① トークンを節約しながら個別指示を修正する場合
- **例: 「星数判定から新しいUGCドメインを除外したい」場合**:
  1. [`workflow/instructions/eval_star_calculator.md`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/instructions/eval_star_calculator.md) だけを開く（他の一切のルールファイルを読まないため、トークン消費はわずか数十行分）。
  2. 除外ドメインリストに該当ドメインを追記。
  3. スクリプト [`workflow/scripts/eval_star_calculator.ps1`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/eval_star_calculator.ps1) の `$excludedDomains` に追加。

### ② スプレッドシートの状態確認のみ行いたい場合
- 巨大な探索スクリプトを動かす必要はありません：
  ```powershell
  powershell -ExecutionPolicy Bypass -Command "& { . 'c:\Users\santa\OneDrive\prideall\projects\kw-serch\workflow\scripts\sheet_data_reader.ps1'; . 'c:\Users\santa\OneDrive\prideall\projects\kw-serch\workflow\scripts\guard_normal_state.ps1'; $d = Read-SheetData; Test-NormalStateStandard -SheetRows $d.RawValues | Format-List }"
  ```

### ③ 新規探索を走らせる場合
- パイプラインランナーを実行：
  ```powershell
  powershell -ExecutionPolicy Bypass -File "c:\Users\santa\OneDrive\prideall\projects\kw-serch\workflow\scripts\workflow_pipeline_runner.ps1" -SeedKeywords @('推し活 100均', '小説 考察') -DryRun
  ```

---

## 4. 厳格ルールの物理的担保（ハードガードレール）

- **第2条（勝手な停止禁止）**: [`guard_quota_monitor`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/guard_quota_monitor.ps1) が物理エラー（403/429/タイムアウト）のみを枯渇と認定。
- **第3条（黄金比率 50:25:25）**: [`portfolio_ratio_balancer`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/portfolio_ratio_balancer.ps1) と [`guard_normal_state`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/guard_normal_state.ps1) が二重でチェック。
- **第4条（正常状態維持）**: 空行ゼロ・該当無しゼロ・ゴミ（★）ゼロを行単位で完全検証。
- **第5条（手戻り根絶・Pre-Write Gate）**: 当たりKWが0件のサイト行は最初からスプシに書き込まない。
- **第6条（ボリューム推測禁止）**: [`research_volume_verifier`](file:///c:/Users/santa/OneDrive/prideall/projects/kw-serch/workflow/scripts/research_volume_verifier.ps1) が実測エビデンスのない手動入力や推測を物理的に遮断。
- **第7条（専用CLI体系）**: 使い捨てスクリプト乱立を完全禁止し、`tools/` 配下の専用ツールのみで運用。
- **第8条（トークン節約鉄則）**: 単発呼び出しを原則禁止し、`match_keywords` / `domain_keywords` によるバルク一括スクリーニングを標準義務化。
