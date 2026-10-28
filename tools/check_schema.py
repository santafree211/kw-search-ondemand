import sqlite3

conn = sqlite3.connect("workflow/data/research.db")
cur = conn.cursor()

for table in ['verified_keywords', 'serp_cache', 'serp_entries']:
    cur.execute(f"PRAGMA table_info({table})")
    cols = [c[1] for c in cur.fetchall()]
    print(f"Table {table}: {cols}")
