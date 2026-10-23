# research_volume_verifier

## 1. 責務（Single Responsibility）
キーワードの月間検索ボリュームを Ubersuggest API（`keyword_overview`）の実測レスポンスに基づいて検証し、1,900以上の基準を満たしているか判定する。また、実測エビデンスをローカルキャッシュ（`verified_volume_cache.json`）に記録する。

## 2. 入力（Input）
- `Keyword`: 検証対象キーワード
- `ApiResponse`: Ubersuggest `keyword_overview` から返却された生JSONオブジェクト（または `search_volume` を含むオブジェクト）
- `CacheFilePath`: 実測キャッシュファイルのパス（デフォルト: `workflow/data/verified_volume_cache.json`）

## 3. 出力（Output）
- `Keyword`: キーワード
- `SearchVolume`: API実測ボリューム
- `Passed`: 判定結果（`SearchVolume >= 1900` ならば True）
- `Evidence`: APIレスポンスエビデンスオブジェクト（タイムスタンプ付き）

## 4. 厳格判定ルール（第6条: Strict Volume Evidence Rule）
1. **推測・仮置き・手動入力の完全禁止**:
   - `search_volume` を手動で代入したり、引数で勝手に仮定することは絶対禁止。
   - 必ず Ubersuggest API のレスポンスJSONから抽出した数値を使用すること。
2. **1,900未満の即時除外**:
   - 実測ボリュームが 1,900 未満（0〜1,899）の場合は、いかなる理由があっても不合格（`Passed = False`）とし、スプレッドシートへ書き込んではならない。
3. **エビデンス記録の義務**:
   - 合格・不合格に関わらず、API実測値は `verified_volume_cache.json` に記録し、後段のガードレール（`guard_normal_state`）が突合できるようにする。
