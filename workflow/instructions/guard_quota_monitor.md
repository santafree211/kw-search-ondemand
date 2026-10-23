# guard_quota_monitor

## 1. 責務（Single Responsibility）
Ubersuggest APIの物理的エラー（HTTP 403, 429, タイムアウト, `daily reports limit reached`）を検知し、主観的・推測による勝手な停止を物理的に遮断するとともに、客観的な「枯渇エビデンス」と「当日の実質APIコール回数（内訳）」を生成・出力する。

## 2. 入力（Input）
- `ErrorText`: API呼び出し時に発生したエラー文字列または例外オブジェクト
- `ApiCallLogs`: 当日のAPI呼び出しログ一覧（呼出時刻、ツール名、引数、ステータス）

## 3. 出力（Output）
- `IsExhausted`: 物理的枯渇判定（True / False）
- `ExhaustionEvidence`: 物理的エラーログのエビデンス文字列
- `TotalCalls`: 当日の実質APIコール総回数
- `CallBreakdown`: ツール別の実質コール回数内訳（`serp_analysis`, `keyword_overview` 等）

## 4. 厳格判定ルール（第2条: Anti-Premature Stop Guard）
1. **主観・推測による停止の完全禁止**:
   - 「100回を超えたから」「そろそろ限界だろう」という主観で停止することは重大規律違反。
2. **停止が許される唯一の基準（ハードストップ）**:
   - `Remote Ubersuggest API request timed out or was temporarily unavailable. Please retry.`
   - `Daily report limit reached`
   - HTTP 429 (Too Many Requests) または HTTP 403 (Forbidden)
3. **エビデンス提示義務**:
   - 探索完了報告時は、直前の物理エラーログと当日の実質コール回数（内訳）の提示を必須とする。
