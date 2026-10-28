import sqlite3

conn = sqlite3.connect("workflow/data/research.db")
cur = conn.cursor()

# Find all keywords in serp_cache that have search volume in verified_keywords
# and calculate star counts
query = """
SELECT se.keyword, vk.volume,
       SUM(CASE WHEN se.position <= 10 AND (se.is_weak_ugc = 1 OR se.is_pure_low_da = 1) THEN 1 ELSE 0 END) as stars
FROM serp_entries se
LEFT JOIN verified_keywords vk ON se.keyword = vk.keyword
GROUP BY se.keyword
HAVING stars >= 2 AND vk.volume >= 1900
ORDER BY stars DESC, vk.volume DESC
"""

cur.execute(query)
rows = cur.fetchall()
print(f"Total Star2+ from full SERP analysis: {len(rows)}")

with open("tools/all_stars_db.txt", "w", encoding="utf-8") as out:
    for kw, vol, stars in rows:
        out.write(f"Stars: {stars} | {kw} (Vol: {vol})\n")

print("Saved to tools/all_stars_db.txt")
