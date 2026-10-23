# sheet_data_reader

## 1. 責務（Single Responsibility）
Google Sheets API経由で、指定スプレッドシートの指定シート（デフォルト: `当たりKW` シート）から最新の全行データを取得し、JSON構造へ変換して返却する。

## 2. 入力（Input）
- `SpreadsheetId`: スプレッドシートID（デフォルト: `1qzhyI8HYRsTyPTyaK7Xnka7PlKAuc3UxpPEaJXj1qTw`）
- `SheetName`: 読み込み対象のシート名（デフォルト: `当たりKW`）
- `Range`: 読み込みセル範囲（デフォルト: `A1:W100`）
- `AccessToken`: Google API Bearerトークン（省略時は `sheet_auth_provider` から自動取得）

## 3. 出力（Output）
- `Header`: 1行目のヘッダー配列
- `Rows`: 2行目以降のデータ行配列（各列値の二次元配列）
- `SiteCount`: 取得したサイト行数
- `RawValues`: APIから返却された生の2次元配列

## 4. 制約・ルール
- シート名に日本語が含まれるため、URLエンコードを確実に行うこと。
- 余計な変更や書き込みは一切行わない（完全リードオンリー）。
