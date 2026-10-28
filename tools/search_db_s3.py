import sqlite3, json

conn = sqlite3.connect("workflow/data/research.db")
cur = conn.cursor()

# Check tables
cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = cur.fetchall()
print("Tables:", tables)

# Search for any star3 keywords in serp_cache or elsewhere
cur.execute("SELECT keyword, volume, star_count, serp_json FROM serp_cache WHERE star_count >= 3")
rows = cur.fetchall()
print(f"Total Star3+ in DB: {len(rows)}")

local_cities = ["東京", "大阪", "名古屋", "福岡", "横浜", "京都", "札幌", "仙台", "神戸", "広島", "埼玉", "千葉", "神奈川", "市", "区", "町", "村", "駅", "県"]

clean_db_s3 = []
for r in rows:
    kw = r[0]
    is_local = False
    for lc in local_cities:
        if lc in kw and lc not in ["市場", "時計", "区別", "時短", "時代"]:
            is_local = True
            break
    if not is_local:
        clean_db_s3.append((kw, r[1], r[2]))

print(f"Clean Star3+ in DB: {len(clean_db_s3)}")
for kw, vol, stars in clean_db_s3[:15]:
    print(f"  {kw} (Vol: {vol}, Stars: {stars})")
