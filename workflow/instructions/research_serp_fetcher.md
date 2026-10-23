# research_serp_fetcher

## 1. 責務（Single Responsibility）
Ubersuggest MCP の `serp_analysis` APIレスポンス（またはSERPログファイル）からGoogle検索結果上位10件のオーガニック情報をパース・抽出し、標準SERPエントリオブジェクトに成形する。

## 2. 入力（Input）
- `Keyword`: 解析対象キーワード
- `SerpApiResponse`: `serp_analysis` からの生JSONレスポンス
- `FilePath`: SERPレスポンスが保存されたローカルファイルパス（任意）

## 3. 出力（Output）
- `Keyword`: キーワード文字列
- `TotalEntries`: 取得エントリ数
- `Top10Organic`: 1〜10位のオーガニック検索エントリ一覧（position, domain, domainAuthority, url, title）

## 4. 制約・ルール
- Google自然検索上位10件（`position 1..10` かつ `type == "organic"`）のみを対象とする。
- ドメイン名は小文字化して正規化する。
