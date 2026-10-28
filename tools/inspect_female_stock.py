import json

with open("workflow/data/shelved_stock_female.json", "r", encoding="utf-8-sig") as f:
    stock = json.load(f)

print(f"Female stock total: {len(stock)}")
s3 = [k for k in stock if k.get('stars', 0) >= 3]
s2 = [k for k in stock if k.get('stars', 0) == 2]
s1 = [k for k in stock if k.get('stars', 0) == 1]

print(f"Star3+: {len(s3)}, Star2: {len(s2)}, Star1: {len(s1)}")

# Filter out local or entertainment from stock candidates as well!
local_cities = ["東京", "大阪", "名古屋", "福岡", "横浜", "京都", "札幌", "仙台", "神戸", "広島", "埼玉", "千葉", "神奈川", "市", "区", "町", "村", "駅", "県"]

clean_s3 = []
for item in s3:
    kw = item.get('keyword', '')
    if not any(lc in kw for lc in local_cities if lc not in ["市場", "時計", "区別", "時短", "時代"]):
        clean_s3.append(item)

clean_s2 = []
for item in s2:
    kw = item.get('keyword', '')
    if not any(lc in kw for lc in local_cities if lc not in ["市場", "時計", "区別", "時短", "時代"]):
        clean_s2.append(item)

print(f"Clean Star3+: {len(clean_s3)}, Clean Star2: {len(clean_s2)}")
print("Sample Clean Star3+:")
for item in clean_s3[:5]:
    print(f"  {item.get('keyword')} ({item.get('volume')}, Stars: {item.get('stars')})")

print("Sample Clean Star2:")
for item in clean_s2[:5]:
    print(f"  {item.get('keyword')} ({item.get('volume')}, Stars: {item.get('stars')})")
