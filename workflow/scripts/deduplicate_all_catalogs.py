"""
deduplicate_all_catalogs.py
責務: 男性50ジャンル・女性50ジャンルのシード群において、
全10,000語（50ジャンル×100語×2）の重複を完全解消し、
ジャンル間・男女間でのシードユニーク性を100%保証する。
将来的な「ジャンル間クロス掛け合わせ（Aジャンル×Bジャンル）」の基盤とする。
"""

import json
import os

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CONFIG_DIR = os.path.join(BASE_DIR, "workflow", "config")

# 高インテント修飾子のプール（約300語）
MODIFIERS_FILE = os.path.join(CONFIG_DIR, "ai_daily_modifiers.json")
with open(MODIFIERS_FILE, "r", encoding="utf-8") as f:
    mod_data = json.load(f)

ALL_MODS = list(mod_data.get("universal_modifiers", []))
for cat_mods in mod_data.get("intent_categories", {}).values():
    ALL_MODS.extend(cat_mods)
ALL_MODS = list(dict.fromkeys(ALL_MODS))  # unique preserving order

def run_global_deduplication():
    male_path = os.path.join(CONFIG_DIR, "genre_catalog_male.json")
    female_path = os.path.join(CONFIG_DIR, "genre_catalog_female.json")

    with open(male_path, "r", encoding="utf-8") as f:
        male_data = json.load(f)
    with open(female_path, "r", encoding="utf-8") as f:
        female_data = json.load(f)

    global_seen = set()

    def process_genres(genres, profile_name):
        for g in genres:
            name = g["name"]
            raw_tokens = name.replace("・", " ").replace("/", " ").replace("(", " ").replace(")", " ").split()
            tokens = [t.strip() for t in raw_tokens if len(t.strip()) >= 2 and t.strip() != "予備枠"]
            if not tokens:
                tokens = [name.strip()]

            new_seeds = []
            
            # 1. 既存シードの中で未登録のものを優先採用
            for s in g.get("seeds", []):
                s_clean = s.strip()
                if s_clean not in global_seen and len(new_seeds) < 100:
                    global_seen.add(s_clean)
                    new_seeds.append(s_clean)

            # 2. 100件に満たない場合、ジャンル固有トークン × 全修飾子プールからユニーク生成
            if len(new_seeds) < 100:
                for t in tokens:
                    for m in ALL_MODS:
                        candidate = f"{t} {m}".strip()
                        if candidate not in global_seen:
                            global_seen.add(candidate)
                            new_seeds.append(candidate)
                        if len(new_seeds) >= 100:
                            break
                    if len(new_seeds) >= 100:
                        break

            # 3. 万が一それでも足りない場合（極端にトークンが少ないジャンル等）
            if len(new_seeds) < 100:
                idx = 1
                for m in ALL_MODS:
                    candidate = f"{tokens[0]} {m} {profile_name}{idx}".strip()
                    if candidate not in global_seen:
                        global_seen.add(candidate)
                        new_seeds.append(candidate)
                        idx += 1
                    if len(new_seeds) >= 100:
                        break

            g["seeds"] = new_seeds[:100]

    # 男性・女性を順番に処理し、全カタログ間で1件たりとも重複しないようにする
    process_genres(male_data["genres"], "男")
    process_genres(female_data["genres"], "女")

    with open(male_path, "w", encoding="utf-8") as f:
        json.dump(male_data, f, ensure_ascii=False, indent=2)
    with open(female_path, "w", encoding="utf-8") as f:
        json.dump(female_data, f, ensure_ascii=False, indent=2)

    total_male = sum(len(g["seeds"]) for g in male_data["genres"])
    total_female = sum(len(g["seeds"]) for g in female_data["genres"])
    print(f"Global deduplication complete!")
    print(f"Male: {len(male_data['genres'])} genres, {total_male} total seeds.")
    print(f"Female: {len(female_data['genres'])} genres, {total_female} total seeds.")
    print(f"Total Unique Seeds across entire system: {len(global_seen)}")

if __name__ == "__main__":
    run_global_deduplication()
