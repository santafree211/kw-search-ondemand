# sheet_auth_provider

## 1. 責務（Single Responsibility）
サービスアカウント秘密鍵JSON（PKCS#8 PEM形式）からJWTを作成・署名し、Google OAuth2トークンエンドポイントから有効なアクセストークンを取得する。

## 2. 入力（Input）
- `KeyPath`: サービスアカウントJSONファイルの絶対パス（省略時はプロジェクト直下のデフォルトキーを使用）

## 3. 出力（Output）
- `AccessToken`: `https://www.googleapis.com/auth/spreadsheets` スコープを持つBearerトークン文字列

## 4. 制約・ルール
- 外部ライブラリ（gcloud CLI等）に依存せず、OS標準機能のみでRSA-SHA256署名を行うこと。
- トークンの有効期限は1時間（3600秒）。
