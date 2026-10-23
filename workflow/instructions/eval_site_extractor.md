# eval_site_extractor

## 1. 責務（Single Responsibility）
星評価を通過した当たりキーワードから、上位10位内にランクインしている実測DA 1〜9の対象サイト情報（サイト名、URL、SiteKey、DA、サイト種別、属性）を抽出し、スプレッドシート行オブジェクトとして成形する。

## 2. 入力（Input）
- `LowDaSites`: `eval_star_calculator` で抽出された実測DA 1〜9のサイト一覧
- `OriginKw`: 発掘起点となったキーワード
- `WinningKws`: そのサイトが保有する当たりキーワード一覧（例: `["☆☆☆キーワード（2400）"]`）

## 3. 出力（Output）
- `SiteRow`: スプレッドシート『当たりKW』シートの各列に対応するオブジェクト
  - `SiteName`: サイト名
  - `Url`: サイトトップURL / 記事URL
  - `SiteKey`: サイト識別キー（ドメイン名）
  - `Da`: 実測DA（1〜9）
  - `SiteType`: サイト種別（特化ブログ、個人サイト、情報ポータル等）
  - `Attribute`: 属性（美容、キャリア、趣味等）
  - `OriginKw`: 発掘起点キーワード
  - `WinningKws`: 当たりキーワード配列（最大15件）

## 4. 制約・ルール
- 当たりキーワードが0件のサイト行は絶対に生成しない（Pre-Write Gate遵守）。
- 大手UGCサイト（note, 知恵袋, アメブロ等）は対象サイトとして抽出しない。
