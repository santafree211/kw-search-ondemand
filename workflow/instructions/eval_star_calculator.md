# eval_star_calculator

## 1. 責務（Single Responsibility）
Ubersuggestの `serp_analysis` レスポンス（Google自然検索上位10件）から「個人が上位を奪取できる席（実測DA 1〜9の独立個人ブログ ＋ 実質DA一桁と判定される弱競合UGCサイト）」を厳密にカウントし、正しい星数（☆1〜☆5）を算出する。

## 2. 入力（Input）
- `Keyword`: 対象キーワード（文字列）
- `SearchVolume`: 実測月間検索ボリューム（整数、1,900以上必須）
- `SerpEntries`: Google検索結果上位10件のエントリ配列（position, type, domain, domainAuthority 等）

## 3. 出力（Output）
- `Keyword`: キーワード文字列
- `SearchVolume`: 検索ボリューム
- `StarCount`: 算出された合計星数（0〜10）
- `WeakUgcCount`: 弱競合UGC（知恵袋、note等）の席数
- `PureLowDaCount`: 実測DA 1〜9の独立個人ブログ数
- `FormattedValue`: スプレッドシート用表記（例: `☆☆☆キーワード（2900）`）。星0個の場合は空文字。
- `IsHit`: 当たりKW条件充足フラグ（`SearchVolume >= 1900` かつ `StarCount >= 1`）
- `LowDaSites`: 判定対象となった全席一覧（個人ブログ ＋ 弱競合UGC）
- `PureLowDaSites`: 実測DA 1〜9の独立個人ブログのみの一覧（スプシ行登録の主語用）
- `WeakUgcSites`: 弱競合UGCのみの一覧

## 4. 厳格判定ルール（鉄則）
1. **上位10位以内のオーガニックのみ対象**: `position 1..10` かつ `type == "organic"` のみカウント。
2. **弱競合UGCの加算判定**:
   - `eval_weak_competitor_rule` により、Yahoo!知恵袋、note、アメブロ、女性向け掲示板、レビュー短文などの「実質DA一桁席」を星加算対象とする。
3. **実測DA 1〜9独立ブログの加算判定**:
   - 実測DA 1〜9の独立ドメイン（個人ブログ）を星加算対象とする。
4. **星0個は除外**: 弱競合席が0件の場合は `IsHit = False`（スプシ登録不可）。
5. **スプシ行登録の主語の保護**: スプレッドシートの行（サイト名・URL・DA）として登録するのは、依然として「実測DA 1〜9の独立個人ブログ（PureLowDaSites）」のみであり、UGC自体を行登録することはない。
