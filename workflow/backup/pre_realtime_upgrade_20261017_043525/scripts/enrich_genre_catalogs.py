"""
enrich_genre_catalogs.py
責務: 男性50ジャンル・女性50ジャンル（計100ジャンル）のカタログシードを
各ジャンル固有のコア名詞×高品質インテント修飾子により、きっちり「1ジャンル100語（計10,000語）」に拡充する。
"""

import json
import os

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CONFIG_DIR = os.path.join(BASE_DIR, "workflow", "config")

HIGH_INTENT_MODIFIERS = [
    "始め方", "使い方", "選び方", "おすすめ", "比較", "レビュー", "評判", "口コミ", "費用", "相場",
    "メリット", "デメリット", "失敗", "注意点", "手順", "やり方", "コツ", "初心者", "ランキング", "人気",
    "手入れ", "保管", "代用", "期間", "頻度", "ブログ", "体験談", "自作", "違い", "買ってよかった",
    "正直レビュー", "使ってみた 感想", "買って後悔", "いらなかった", "やめた理由", "失敗談 ブログ", "どっちがいい",
    "安くて良い", "元が取れる", "長持ちさせる方法", "初心者が揃えるもの", "最初に買うなら", "失敗しない選び方",
    "使いこなす コツ", "買ってはいけない", "プロのおすすめ", "寿命 どのくらい", "修理 自分で", "買い替え サイン",
    "時短 テクニック", "コスパ最強", "型落ち 狙い目", "本音レビュー", "壊れやすいか", "耐久性 検証", "必要か いらないか",
    "代用品 おすすめ", "一人暮らし 必要なもの", "初期費用 抑える", "手入れ 楽なもの", "安く揃える コツ", "ステマなし",
    "愛用歴", "リアルな口コミ", "ぶっちゃけ", "リピート買い", "乗り換えた理由", "家族の評判", "コスパ比較",
    "維持費 どのくらい", "型番 違い", "上位モデル 必要か", "下位モデル 十分", "中古 注意点", "セール 時期",
    "安く買う方法", "自力で直す", "簡単 メンテ", "トラブル 解決", "原因 対策", "直らない 対処", "落とし方 簡単",
    "長持ち コツ", "臭い 取り方", "汚れ 落ちない", "直し方 簡単", "傷 消し 自分で", "動かない 原因", "音がうるさい 対策",
    "生活の質 向上", "時間短縮 効果", "買って暮らしが変わった", "3ヶ月使った本音", "1年後の耐久性", "買い替え サイクル",
    "日常 お手入れ", "素直な感想", "期待外れだった点", "買って大正解", "もっと早く買えばよかった", "手放せない 理由"
]

def enrich_file(filename):
    file_path = os.path.join(CONFIG_DIR, filename)
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    total_genres = len(data["genres"])
    for g in data["genres"]:
        name = g["name"]
        seeds = list(g.get("seeds", []))
        
        # トークン分割（ジャンル名に含まれる名詞群）
        raw_tokens = name.replace("・", " ").replace("/", " ").replace("(", " ").replace(")", " ").split()
        tokens = [t.strip() for t in raw_tokens if len(t.strip()) >= 2 and t.strip() != "予備枠"]
        if not tokens:
            tokens = [name.strip()]

        # トークン × 高インテント修飾子 でシードを増強
        for t in tokens:
            for mod in HIGH_INTENT_MODIFIERS:
                kw = f"{t} {mod}"
                if kw not in seeds:
                    seeds.append(kw)
                if len(seeds) >= 100:
                    break
            if len(seeds) >= 100:
                break
        
        # 100語に確定
        g["seeds"] = seeds[:100]

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    counts = [len(g["seeds"]) for g in data["genres"]]
    print(f"Successfully enriched {filename}: {total_genres} genres, min={min(counts)}, max={max(counts)}.")

if __name__ == "__main__":
    enrich_file("genre_catalog_male.json")
    enrich_file("genre_catalog_female.json")
