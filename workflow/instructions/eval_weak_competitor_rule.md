# eval_weak_competitor_rule

## 1. 責務（Single Responsibility）
指定されたドメインまたはURLが、「実質DA一桁（個人特化ブログで上位奪取が容易な弱競合UGC・Q&A・素人投稿プラットフォーム）」に該当するかどうかを厳密に判定する。

## 2. 背景・判定理由
Google検索結果（SERP）上位において、ドメインパワー（DA 70〜90超）自体の下駄によって一時的にランクインしているが、コンテンツの実態が以下であるページは、実戦SEOにおいて「個人ブログで抜ける席（実質DA一桁相当）」として星数カウントに加算する：
1. **Q&A・知恵袋**: 素人の短文回答、主観、誤情報、SEO構造化なし。
2. **女性コミュニティ・掲示板**: 匿名ユーザーの雑談、愚痴、スレッド形式の断片テキスト。
3. **無料ブログ・日記**: 個人ユーザーの日常雑記、写真数枚の感想文、見出し設計なし。
4. **レビュー・感想SNS**: 読書メーター、Filmarks、つぶやき等の短文（250文字前後）。
5. **画像中心UGC**: RoomClip、Lemon8等の画像メインでテキスト解説が極小な投稿。

## 3. 入力（Input）
- `Domain`: ドメイン文字列（例: `chiebukuro.yahoo.co.jp`, `note.com`）
- `Url`: 任意。個別ページURL（パスによる絞り込みが必要な場合に使用、例: `cookpad.com/recipe/`）

## 4. 出力（Output）
- `IsWeakCompetitor`: 対象が弱競合UGCに該当するか（`$true` / `$false`）
- `Category`: マッチしたカテゴリ名（`qa_community`, `women_community`, `free_blog_diary`, `review_culture`, `lifestyle_ugc`, `curation_sns_bbs`, `free_wiki_homepage` 等）
- `CategoryName`: カテゴリの表示名
- `MatchedPattern`: 判定に合致した正規表現パターン
- `Reason`: 弱競合と判定される理由

## 5. 設計原則（Pure ASCII / JSON外出し）
- パターン定義は `workflow/data/weak_competitor_patterns.json` から動的ロード。
- JSONが存在しない場合でも主要ドメイン（知恵袋、note、アメブロ、教えてgoo等）はコード内フォールバックで保証。
- PowerShellスクリプトはShift-JIS環境を考慮し、Pure ASCIIで記述。
