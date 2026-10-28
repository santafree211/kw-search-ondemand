# ワークスペース自動実行・常時稼働ルール (kw-serch)

## 1. 3大絶対原則 (Core Standards)

### 第1条: 50ジャンル均等底上げ (Parallel Water-Leveling Standard)
* **特定ジャンル偏重の禁止**: マンガ・映画・エンタメ、100均グッズなど特定ジャンルのみの集中探索を厳禁とし、50ジャンルを均等に並行して底上げする（初期目標: 全ジャンル18件以上、最終目標: 各ジャンル300件/計15,000件（星3以上: 150件/ジャンル））。
* **シード枯渇時の自律深掘り**: カタログ初期シードが消化されたジャンルは、無差別キーワードに脱線せず、同一ジャンル内のコア単語からロングテールキーワード（2語・3語サジェスト）を自律派生して深掘りすること。

### 第2条: 『当たりKW』シートの黄金比率維持 (50:25:25 Golden Ratio Standard)
* **品質基準 (全体合算)**:
  * **☆☆☆以上**: **50%以上**（最重要品質基準：☆☆☆が全体の過半数を維持）
  * **☆☆**: **25%以下**（☆☆☆の半数以下）
  * **☆**: **25%以下**（☆☆☆の半数以下）
  * **バランス維持**: ☆☆と☆の件数差は最大1件以内（1:1同数バランス）。
* **スプシ行登録の主語の保護**: スプレッドシートの行（サイト名・URL・DA）として登録するのは**実測DA 1〜9の独立個人ブログのみ**（弱競合UGC自身を行登録することは厳禁）。

### 第3条: 3者突合照合監査と実測エビデンス (Triple Reconciliation Standard)
* **完全一致の義務**: スプレッドシート ✕ ルール ✕ Ubersuggest生データ（DA・Vol・星数）の完全一致（違反0件）を維持すること。
* **検索ボリューム実測**: 推測・仮置きは厳禁。Ubersuggest API生レスポンスに基づく月間ボリューム1,900以上の生データのみ有効。
* **星数（☆）の判定鉄則**: 検索結果上位10位以内の「個人で抜ける席（実測DA 1〜9の独立個人ブログ ＋ 実質DA一桁の弱競合UGC: Yahoo!知恵袋、note、アメブロ、教えて!goo、ガールズちゃんねる等）」の合計数で決定。

### 第4条: 日次1回AIシード思考プロトコル (Daily 1-Shot AI Modifier Enrichment)
* **トークン最小化とシード枯渇予防の両立**: 実行中のループ内で都度LLMを呼ぶことを厳禁とし、1日に1回のみ（日次リサーチ開始時または朝9時リセット時）、AI（エージェント）が検索意図（悩み・比較・体験談・費用・トラブル解決等）を深く思考して `workflow/config/ai_daily_modifiers.json` を一括更新・補充する。
* **動的シード適用**: `workflow/scripts/genre_seed_expander.ps1` は本ファイルを自動読み込みし、50ジャンル全域でシード枯渇（空回り）を恒久予防する。

### 第5条: デイリー上限完全活用・日次常時探索原則 (Daily Quota Maximization Standard)
* **デイリー上限の完全消化**: 毎日の探索枠（09:00 JSTリセット）を最大限に活用し、Ubersuggestの物理的デイリー上限に達するか、あるいは当日の修飾子探索が一巡するまで、毎日欠かさず当たりKW（☆☆☆過半数）を徹底探索・登録すること。
* **翌日への継承**: 日次上限到達または修飾子消化で終了した後は、翌朝9時のリセットに合わせて第4条（日次1回AI思考）で新たな修飾子を補充し、翌日の探索へと自律継続する。

---

## 2. 唯一の標準実行・監査コマンド体系 (Single Tools)
アドホックなスクリプト作成や旧スクリプトの使用は禁止。以下の正規ツールのみを使用すること：

1. **唯一の自律実行エントリポイント (男女交互均等底上げ)**:
   `powershell -ExecutionPolicy Bypass -File tools\run_pipeline.ps1 [-DryRun] [-Gender both|female|male]`
2. **日次完全パッケージ (ワンクリック・バッチ・タスク統合実行)**:
   `.\run_daily.bat` または `powershell -ExecutionPolicy Bypass -File tools\run_daily_package.ps1 [-Gender both|female|male] [-DryRun]`
3. **Windowsタスクスケジューラ管理 (朝9:15自動巡回登録/解除)**:
   `powershell -ExecutionPolicy Bypass -File tools\register_scheduled_task.ps1 -Action Register|Unregister|Status|RunNow [-DailyTime "09:15"]`
4. **唯一の3者突合照合監査 (スプシ✕ルール✕生データ)**:
   `powershell -ExecutionPolicy Bypass -File tools\sheet_reconcile.ps1 [-Gender both|female|male]`
5. **シート健全性監査 (黄金比率・フォーマット検証)**:
   `powershell -ExecutionPolicy Bypass -File tools\sheet_audit.ps1 [-Gender both|female|male]`
6. **50ジャンル進捗・水位確認**:
   `powershell -ExecutionPolicy Bypass -File tools\genre_inspect.ps1 [-Gender both|female|male]`
7. **シート登録行確認**:
   `powershell -ExecutionPolicy Bypass -File tools\sheet_inspect.ps1 [-Gender both|female|male] [-EndRow N]`
8. **安全サイトコミット**:
   `powershell -ExecutionPolicy Bypass -File tools\sheet_commit.ps1 -SiteName "<名前>" -Url "<URL>" -Da <DA> -WinningKws @('<KW>') -Gender <female|male> -GenreNumber <M-xx|F-xx> -GenreName "<ジャンル名>"`

---

## 3. 停止基準と終了時監査義務 (Exit Audit Protocol)
* **客観的停止基準**:
  * `Daily report limit reached` または HTTP `429 Too Many Requests` / `403 Forbidden`（物理的API枯渇時のみ）。
  * 一時的な通信タイムアウト時は MCP通信基盤による自動リトライで自己修復を図り、安易な主観的中断を禁止する。
* **終了時監査義務**:
  * タスク終了時は、必ず `tools\sheet_reconcile.ps1` を実行し、男女両シートの3者突合（Passed: true）および黄金比率適合を確認・報告すること。
