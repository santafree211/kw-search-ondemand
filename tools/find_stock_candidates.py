import json

with open("workflow/data/shelved_stock_female.json", "r", encoding="utf-8-sig") as f:
    stock = json.load(f)

local_cities = ["東京", "大阪", "名古屋", "福岡", "横浜", "京都", "札幌", "仙台", "神戸", "広島", "埼玉", "千葉", "神奈川", "市", "区", "町", "村", "駅", "県"]

s3_candidates = []
s2_candidates = []

for item in stock:
    # item looks like: "☆☆☆キーワード(ボリューム)" or "☆☆キーワード(ボリューム)"
    is_local = False
    for lc in local_cities:
        if lc in item:
            if lc not in ["市場", "時計", "区別", "時短", "時代"]:
                is_local = True
                break
    if is_local:
        continue
        
    if item.startswith("☆☆☆") or "⭐⭐⭐" in item:
        s3_candidates.append(item)
    elif item.startswith("☆☆") or "⭐⭐" in item:
        s2_candidates.append(item)

with open("tools/stock_candidates.txt", "w", encoding="utf-8") as out:
    out.write(f"S3 count: {len(s3_candidates)}, S2 count: {len(s2_candidates)}\n\n")
    out.write("S3:\n")
    for s in s3_candidates[:20]:
        out.write(f"  {s}\n")
    out.write("\nS2:\n")
    for s in s2_candidates[:20]:
        out.write(f"  {s}\n")

print("Candidates saved to tools/stock_candidates.txt")
