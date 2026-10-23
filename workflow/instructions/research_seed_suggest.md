# research_seed_suggest

## 1. 責務（Single Responsibility）
起点キーワードまたはテーマからサジェスト・関連語（Ubersuggest `keyword_suggestions` / `google_suggestions` や候補リスト）を収集し、重複や不要文字を除去した候補キーワードリストを生成する。

## 2. 入力（Input）
- `SeedKeywords`: 起点キーワード配列（例: `["推し活", "小説 考察", "行政書士"]`）
- `RawSuggestions`: APIから返却されたサジェスト一覧（またはテキストファイル）
- `ExcludeExisting`: スプレッドシート登録済みキーワード一覧（重複排除用）

## 3. 出力（Output）
- `CandidateKeywords`: 重複排除・正規化済みの候補キーワード配列
- `TotalCandidates`: 抽出件数

## 4. 制約・ルール
- 全角・半角スペースの統一（半角スペース1つへ正規化）。
- 特殊記号（★、☆、括弧など）の除去。
- 既存シート登録済みキーワードとの完全一致重複を自動排除。
