# guard_normal_state

## 1. 責務（Single Responsibility）
スプレッドシート『当たりKW』シートを更新する前に、更新予定データが「正常状態基準（Normal State Standard）」を100%満たしているかを機械的に全件検証する最上位ガードレールゲート。

## 2. 入力（Input）
- `SheetRows`: 更新予定の全行データ（ヘッダー行＋データ行）
- `VerifiedVolumeMap`: 実測APIログ突合用ハッシュマップ（キーワード ➔ 実測ボリューム）
- `VerifiedCachePath`: 実測キャッシュJSONのパス（デフォルト: `workflow/data/verified_volume_cache.json`）

## 3. 出力（Output）
- `Passed`: 検証合否判定（True / False）。1件でも違反があれば False。
- `Errors`: 検出されたエラー内容の一覧（配列）
- `SiteCount`: サイト数
- `TotalKeywords`: 全当たりキーワード件数
- `Star3Count` / `Star2Count` / `Star1Count`: 星ごとの件数
- `Ratios`: 各星のパーセンテージ

## 4. 厳格検証ルール（鉄則）
1. **空行・該当無し行の完全排除**:
   - 行間に空行が存在する場合は即座にエラー。
   - 当たりKWが空、または「該当無し」の行が存在する場合は即座にエラー。
2. **ゴミ・水増しの完全排除**:
   - 黒星「★」や不正文字が含まれるセルは即座にエラー。
3. **ボリューム1,900以上の物理的検証（第6条）**:
   - 括弧内の数値が 1,900 未満（例: `(0)` や `(260)`）の場合は即座にエラー。
   - `VerifiedVolumeMap` または `verified_volume_cache.json` と突合し、API実測エビデンスが存在しないキーワード、または実測値が1,900未満のものは即座にエラー。
4. **黄金比率の厳格維持（第3条）**:
   - 全KW合算で【☆3以上 >= 50.0%、☆2 = 25.0%、☆1 = 25.0%】でなければ即座にエラー。
