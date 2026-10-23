# sheet_atomic_writer

## 1. 責務（Single Responsibility）
ガードレール（`guard_normal_state`）を100%通過した行データのみを受け取り、Google Sheets APIを通じてスプレッドシート（『当たりKW』シート）へ一括アトミック更新（全域クリア ➔ 新規一括書き込み）を実行する。

## 2. 入力（Input）
- `SpreadsheetId`: スプレッドシートID
- `SheetName`: 対象シート名（デフォルト: `当たりKW`）
- `SheetRows`: 書き込み対象の全行2次元配列（ヘッダー行＋データ行）
- `AccessToken`: Google API Bearerトークン（省略時は `sheet_auth_provider` から自動取得）
- `ClearRange`: 事前消去範囲（デフォルト: `A1:W60`）

## 3. 出力（Output）
- `Status`: `Success` または `Failed`
- `UpdatedRows`: 反映された行数
- `UpdatedCells`: 反映されたセル数
- `Timestamp`: 更新完了タイムスタンプ

## 4. 厳格判定ルール（第4条 & 第5条: Atomic Pre-Validation Standard）
1. **書き込み前ガードレール強制実行（Pre-Write Gate）**:
   - 必ず事前に `guard_normal_state`（`Test-NormalStateStandard`）を実行し、**Passed: True** が返らない限り、Google Sheets API の更新エンドポイントを絶対に叩いてはならない。
2. **アトミック更新（全域クリア ➔ 一括書き込み）**:
   - 行の追記ではなく、事前クリアを行った上で隙間なく詰めた状態を一括PUTすることで、残存ゴミ行・空白行の混入を物理的に排除する。
3. **UTF-8エンコード保証**:
   - 日本語および特殊記号（☆、全角括弧）の文字化けを防ぐため、リクエストBodyはUTF-8バイト列で送信する。
