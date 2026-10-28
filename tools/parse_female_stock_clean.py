import json

with open("workflow/data/shelved_stock_female.json", "r", encoding="utf-8-sig") as f:
    female_stock = json.load(f)

local_cities = ["東京", "大阪", "名古屋", "福岡", "横浜", "京都", "札幌", "仙台", "神戸", "広島", "埼玉", "千葉", "神奈川", "市", "区", "町", "村", "駅", "県"]

clean_s2 = []
for item in female_stock:
    # check if local
    if any(lc in item for lc in local_cities if lc not in ["市場", "時計", "区別", "時短", "時代"]):
        continue
    clean_s2.append(item)

print(f"Total clean S2 in female stock: {len(clean_s2)}")
for s in clean_s2[:20]:
    print(s)
