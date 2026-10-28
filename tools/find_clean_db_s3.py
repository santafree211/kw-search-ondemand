import sqlite3

conn = sqlite3.connect("workflow/data/research.db")
cur = conn.cursor()

# Find keywords with >= 3 weak/pure seats in top 10
query = """
SELECT se.keyword, vk.volume, COUNT(*) as star_count
FROM serp_entries se
JOIN verified_keywords vk ON se.keyword = vk.keyword
WHERE se.position <= 10 AND (se.is_weak_ugc = 1 OR se.is_pure_low_da = 1)
GROUP BY se.keyword, vk.volume
HAVING star_count >= 3 AND vk.volume >= 1900
ORDER BY star_count DESC, vk.volume DESC
"""

cur.execute(query)
rows = cur.fetchall()
print(f"Total Star3+ in DB: {len(rows)}")

local_cities = ["東京", "大阪", "名古屋", "福岡", "横浜", "京都", "札幌", "仙台", "神戸", "広島", "埼玉", "千葉", "神奈川", "市", "区", "町", "村", "駅", "県"]

clean_s3 = []
for kw, vol, stars in rows:
    if not any(lc in kw for lc in local_cities if lc not in ["市場", "時計", "区別", "時短", "時代"]):
        clean_s3.append((kw, vol, stars))

print(f"Clean Star3+ in DB: {len(clean_db_s3 if 'clean_db_s3' in locals() else clean_s3)}")
with open("tools/clean_db_s3.txt", "w", encoding="utf-8") as out:
    for kw, vol, stars in clean_s3:
        out.write(f"Stars: {stars} | {kw} ({vol})\n")
print("Saved to tools/clean_db_s3.txt")
