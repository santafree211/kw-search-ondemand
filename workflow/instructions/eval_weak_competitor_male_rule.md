# eval_weak_competitor_male_rule

## 1. 責務（Single Responsibility）
男性向け意図キーワード（ビジネス、キャリア、趣味、IT・ガジェット、男性の悩み等）において、
指定されたドメインまたはURLが「実質DA一桁（個人特化ブログで上位奪取が容易な弱競合UGC・Q&A・素人投稿・掲示板）」に該当するか判定する。

## 2. 判定対象カテゴリ（男性KW用）
1. `qa_community`: Yahoo!知恵袋、教えて!goo、OKWAVE、Quora、はてな人力検索、質問箱、マシュマロ、Mond 等
2. `curation_sns_bbs`: 5ch、2ch.sc、おーぷん2ch、Togetter、min.t、はてブエントリー 等
3. `knowledge_experience_ugc`: note、Qiita、Zenn、teratail（個人の日常雑記、短文エラーメモ、体験記）
4. `subculture_review_wiki`: 読書メーター、ブクログ、Filmarks、アットウィキ、WIKIWIKI、Seesaa Wiki、なろう、カクヨム
5. `free_blog_diary`: はてなブログ、ライブドアブログ、FC2ブログ、アメブロ、Seesaa、goo、楽天ブログ、エキサイト、ココログ

※女性専用UGC（ガールズちゃんねる、ママスタ、ママリ、LIPS等）は除外。
※企業攻略メディア（GameWith、価格.com等）は組織的制作のため弱競合枠（実質DA一桁）から除外。

## 3. 入力と出力
- 入力: `Domain` (string), `Url` (string)
- 出力: `IsWeakCompetitor` (bool), `Category` (string), `CategoryName` (string), `MatchedPattern` (string), `Reason` (string)
