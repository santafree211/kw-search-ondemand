# eval_star_calculator_male

## 1. 責務（Single Responsibility）
男性向けキーワードにおいて、検索結果上位10位以内のオーガニック結果から：
1. **実測DA 1〜9の独立個人ブログ**
2. **男性向け弱競合UGC（実質DA一桁枠）**
の合計席数を「個人で抜ける席」として合算カウントし、厳格な☆数（☆☆☆、☆☆、☆）を算出する。

## 2. 鉄則・境界線（スプシ行登録の主語の保護）
- 星数（☆）の加算対象には弱競合UGCを含めるが、
  **スプレッドシートの行（サイト名・URL・DA）として登録する主語は、依然として「実測DA 1〜9の独立個人ブログ」のみ**とする。
- UGC自身（noteや知恵袋、5chなど）を行登録することは厳禁。
- 弱競合席が1件以上あっても、10位以内に実測DA 1〜9の独立個人ブログが0件の場合は `HasRegisterableSubject = false` となり、行登録不可とする。

## 3. 入力と出力
- 入力: `Keyword` (string), `SearchVolume` (int), `SerpEntries` (array)
- 出力: `StarCount` (int), `WeakUgcCount` (int), `PureLowDaCount` (int), `FormattedValue` (string), `IsHit` (bool), `WinningSeats` (array), `PureLowDaSites` (array), `WeakUgcSites` (array), `HasRegisterableSubject` (bool)
