# portfolio_ratio_balancer

## 1. 責務（Single Responsibility）
スプレッドシート全体の全当たりキーワードにおける黄金比率（☆☆☆以上: 50%以上、☆☆: 25%、☆: 25%）を維持するための投入可能枠（Slot Pre-Allocation）を計算し、比率を崩すキーワードを一時退避ストック（`shelved_stock.json`）へ配分する。

## 2. 入力（Input）
- `CurrentKeywords`: 現行スプレッドシートに登録されている全キーワード配列（星プレフィックス付き）
- `NewKeywords`: 新規に合格した候補キーワード配列（星プレフィックス付き）
- `ShelvedStockPath`: 一時退避ストックのファイルパス（デフォルト: `workflow/data/shelved_stock.json`）

## 3. 出力（Output）
- `CanCommit`: スプレッドシート投入可能フラグ（比率が合致するか）
- `CommitKeywords`: 今回スプレッドシートへ投入可能なキーワード一覧
- `ShelvedKeywords`: ストックへ一時退避すべきキーワード一覧
- `ResultingRatio`: 投入後の予想比率（Star3Pct, Star2Pct, Star1Pct）

## 4. 厳格判定ルール（第3条 & 第5条: Portfolio Allocation Standard）
1. **シート全体の合算で判定**:
   - 新規追加分のみの比率ではなく、スプレッドシート全体の全KW合算で【☆3以上 >= 50%、☆2 = 25%、☆1 = 25%】を維持すること。
2. **先行枠制御（Slot Pre-Allocation）**:
   - 単体で☆1や☆2が見つかっても、シート全体の黄金比率を崩す場合はシートに書き込まず、ローカルストック（`shelved_stock.json`）に保持する。
   - ☆3以上のキーワードとセットで比率が維持できる確定タイミングでのみ、シートへ一括投入する。
