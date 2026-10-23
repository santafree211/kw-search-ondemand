import json
import re
import urllib.request
import subprocess
from datetime import datetime

# 1. Acquire Google API Token
token = subprocess.check_output([
    'powershell', '-ExecutionPolicy', 'Bypass', '-Command',
    '. .\\workflow\\scripts\\sheet_auth_provider.ps1; Get-GoogleAccessToken'
]).decode('utf-8').strip()

SPREADSHEETS = {
    "male": {
        "id": "1ZFYMVVc10cZISofcB71x6ICt9ejZyGLzmVgpKbXvR40",
        "title": "KWagent (男性用)",
        "kw_start_col": 6
    },
    "female": {
        "id": "1qzhyI8HYRsTyPTyaK7Xnka7PlKAuc3UxpPEaJXj1qTw",
        "title": "（女性）KWagent",
        "kw_start_col": 8
    }
}

MALE_CATEGORY_RULES = [
    {
        "category": "漫画・アニメ・ネタバレ・考察",
        "patterns": ["漫画", "アニメ", "ネタバレ", "完結", "考察", "キャラ", "打ち切り", "あらすじ", "死亡", "結末", "最終回", "総集編", "相関図", "チェンソーマン", "フリーレン", "薬屋のひとりごと", "ホタルの嫁入り", "ガチアクタ", "呪術廻戦", "ハンターハンター", "光が死んだ夏", "ひぐらし", "方舟", "近畿地方", "怪物", "ねずみの初恋", "ジャンケットバンク", "フェルマーの料理", "影の実力者", "シュタインズゲート", "俺だけレベルアップ", "十角館", "凪のお暇", "私の夫と結婚して", "春の嵐とモンスター", "さよならお兄ちゃん", "徒花", "今際の国のアリス", "異国日記", "誰も知らない", "物語シリーズ", "化物語", "ダンまち", "ヘスティア"]
    },
    {
        "category": "映画・ドラマ・VOD・芸能",
        "patterns": ["映画", "ドラマ", "Netflix", "VOD", "動画配信", "実写", "Snow Man", "ファンクラブ", "舞台", "俳優", "主題歌"]
    },
    {
        "category": "本・小説・読書・教養",
        "patterns": ["小説", "本", "読書", "恩田陸", "伊坂幸太郎", "東野圭吾", "辻村深月", "加賀恭一郎", "純文学", "Kindle", "マスカレード", "昔の言葉", "ことわざ", "慣用句", "十二国記", "湊かなえ"]
    },
    {
        "category": "サウナ・温泉・銭湯・レジャー",
        "patterns": ["サウナ", "温泉", "スーパー銭湯", "銭湯", "ふろ屋", "ととのう", "日の本湯", "the spa 成城"]
    },
    {
        "category": "筋トレ・フィットネス・スポーツ",
        "patterns": ["筋トレ", "パーソナルジム", "プロテイン", "ベンチプレス", "ジム", "ゴルフ", "ドライバー", "スイング", "飛距離"]
    },
    {
        "category": "趣味・ホビー・模型・サブカル",
        "patterns": ["プラモデル", "ガンプラ", "模型", "フィギュア", "ミニ四駆", "ボードゲーム", "ドラクエ", "ゲーム", "PS5", "Switch", "レトロゲーム"]
    },
    {
        "category": "アウトドア・キャンプ・料理",
        "patterns": ["キャンプ", "焚き火", "二次燃焼", "登山", "釣り", "キャンプ飯", "メスティン", "燻製", "ホットサンド", "ダッチオーブン"]
    },
    {
        "category": "バイク・自動車・サイクリング",
        "patterns": ["バイク", "ツーリング", "ロードバイク", "クロスバイク", "サイクリング", "洗車", "コーティング", "車中泊", "ドライブ"]
    },
    {
        "category": "音楽・楽器・オーディオ",
        "patterns": ["ギター", "ベース", "エフェクター", "DTM", "オーディオ", "スピーカー", "アンプ", "DAC", "ホームシアター", "レコード"]
    },
    {
        "category": "クラフト・革製品・文具・アクアリウム",
        "patterns": ["靴磨き", "革靴", "レザークラフト", "エイジング", "革財布", "万年筆", "手帳", "文房具", "アクアリウム", "熱帯魚", "メダカ", "水草", "ビカクシダ"]
    },
    {
        "category": "IT・ガジェット・PC・通信",
        "patterns": ["PC", "自作PC", "グラボ", "GPU", "ガジェット", "ドローン", "免許", "スマホ", "SIM", "Wi-Fi", "モニター", "キーボード", "スマートウォッチ", "イヤホン"]
    },
    {
        "category": "仕事・転職・退職・キャリア・資格",
        "patterns": ["仕事", "辞める", "退職", "転職", "有休", "有給", "行きたくない", "会社", "部活", "休む理由", "簿記", "資格", "履歴書", "面接", "在宅", "クラウドソーシング"]
    },
    {
        "category": "暮らし・手続き・マナー・家族",
        "patterns": ["行政書士", "内容証明", "家族とは", "墓じまい", "絶縁状", "冠婚葬祭", "マナー", "手続き"]
    },
    {
        "category": "暮らし・生活・便利・節約・買取",
        "patterns": ["出張買取", "買取", "クーポン", "ベネフィット", "benefit", "松のや", "しゃぶ葉", "浄水器", "ウォーターサーバー", "ポータブル電源", "ポイ活", "節約", "食パン", "朝ごはん", "クルミッ子", "お土産", "手土産", "東京駅", "おもちゃ サブスク", "断捨離"]
    },
    {
        "category": "インテリア・家具・デスク環境",
        "patterns": ["インテリア", "IKEA", "昇降デスク", "模様替え", "部屋", "収納", "クローゼット", "片付け", "家具", "デスク"]
    },
    {
        "category": "占い・手相・スピリチュアル・心理",
        "patterns": ["占い", "手相", "タロット", "スピリチュアル", "スター線", "チャットgpt手相", "合唱コンクール", "スローガン", "縁を切る", "婿養子", "自己肯定感", "心理テスト", "診断"]
    },
    {
        "category": "100均・雑貨・推し活・DIY",
        "patterns": ["100均", "ダイソー", "セリア", "キャンドゥ", "スリコ", "推し活", "痛バ", "痛ロゼット", "トレカケース", "うちわ", "アクスタ", "スリーブ", "モール", "硬質ケース", "缶バッジ", "アクリル板", "ナスカン", "カードスタンド", "DIY", "ペンキ"]
    }
]

FEMALE_CATEGORY_RULES = [
    {
        "category": "漫画・アニメ・ネタバレ・考察",
        "patterns": ["漫画", "アニメ", "ネタバレ", "完結", "考察", "キャラ", "打ち切り", "あらすじ", "死亡", "結末", "最終回", "総集編", "相関図", "チェンソーマン", "フリーレン", "薬屋のひとりごと", "ホタルの嫁入り", "ガチアクタ", "呪術廻戦", "ハンターハンター", "光が死んだ夏", "ひぐらし", "方舟", "近畿地方", "怪物", "ねずみの初恋", "ジャンケットバンク", "フェルマーの料理", "影の実力者", "シュタインズゲート", "俺だけレベルアップ", "十角館", "凪のお暇", "私の夫と結婚して", "春の嵐とモンスター", "さよならお兄ちゃん", "徒花", "今際の国のアリス", "異国日記", "誰も知らない", "物語シリーズ", "化物語"]
    },
    {
        "category": "映画・ドラマ・VOD・芸能",
        "patterns": ["映画", "ドラマ", "Netflix", "VOD", "動画配信", "実写", "Snow Man", "ファンクラブ", "舞台", "俳優", "主題歌"]
    },
    {
        "category": "本・小説・読書・教養",
        "patterns": ["小説", "本", "読書", "恩田陸", "伊坂幸太郎", "東野圭吾", "辻村深月", "加賀恭一郎", "純文学", "Kindle", "マスカレード", "昔の言葉", "ことわざ", "慣用句"]
    },
    {
        "category": "100均・推し活・雑貨・DIY",
        "patterns": ["100均", "ダイソー", "セリア", "キャンドゥ", "スリコ", "推し活", "痛バ", "痛ロゼット", "トレカケース", "うちわ", "アクスタ", "スリーブ", "モール", "硬質ケース", "缶バッジ", "アクリル板", "ナスカン", "カードスタンド", "DIY", "ペンキ"]
    },
    {
        "category": "手芸・ハンドメイド・刺繍・編み物",
        "patterns": ["編み物", "かぎ針", "手芸", "ブランケット", "毛糸", "レジン", "アクセサリー 作り方", "手作り", "刺繍", "クロスステッチ", "図案"]
    },
    {
        "category": "食器・うつわ・キッチングッズ・お弁当",
        "patterns": ["食器", "うつわ", "波佐見焼", "イッタラ", "陶器市", "よしざわ窯", "お弁当", "曲げわっぱ", "スープジャー", "常備菜"]
    },
    {
        "category": "文房具・手帳デコ・シール",
        "patterns": ["手帳", "ほぼ日", "ロルバーン", "マスキングテープ", "マステ", "文房具", "シール", "コラージュ"]
    },
    {
        "category": "カフェ・純喫茶・お茶・スイーツ",
        "patterns": ["純喫茶", "喫茶店", "プリン", "カフェ", "アフタヌーンティー", "スイーツ", "クリームソーダ", "紅茶", "ハーブティー", "お茶"]
    },
    {
        "category": "暮らし・掃除・植物・生活ハック",
        "patterns": ["重曹", "クエン酸", "オキシ漬け", "ウタマロ", "洗濯", "観葉植物", "多肉植物", "ガーデニング", "ベランダ菜園", "出張買取", "買取", "クーポン", "ベネフィット", "松のや", "しゃぶ葉", "浄水器", "ウォーターサーバー", "ポータブル電源", "ポイ活", "節約", "食パン", "朝ごはん", "クルミッ子", "お土産", "手土産", "東京駅"]
    },
    {
        "category": "インテリア・家具・収納",
        "patterns": ["インテリア", "北欧", "IKEA", "昇降デスク", "模様替え", "部屋", "収納", "クローゼット", "片付け", "家具"]
    },
    {
        "category": "温泉・サウナ・女子旅・リフレッシュ",
        "patterns": ["サウナ", "温泉", "スーパー銭湯", "岩盤浴", "女子旅", "ホテルステイ", "旅行", "アロマ", "入浴剤"]
    },
    {
        "category": "仕事・キャリア・資格・在宅ワーク",
        "patterns": ["仕事", "辞める", "退職", "転職", "有休", "有給", "行きたくない", "会社", "部活", "休む理由", "簿記", "資格", "履歴書", "面接", "在宅", "ライター"]
    },
    {
        "category": "占い・手相・スピリチュアル・心理",
        "patterns": ["占い", "手相", "タロット", "スピリチュアル", "スター線", "チャットgpt手相", "合唱コンクール", "スローガン", "縁を切る", "婿養子", "自己肯定感", "心理テスト", "診断"]
    },
    {
        "category": "育児・キッズ・入園準備",
        "patterns": ["入園", "名前シール", "通園バッグ", "離乳食", "ベビーカー", "抱っこ紐", "知育玩具", "おもちゃ"]
    },
    {
        "category": "過去登録・美容（※新規探索停止）",
        "patterns": ["ディノベート", "まつ毛パーマ", "コスメ", "メイク", "スキンケア", "脱毛"]
    }
]

def classify_kw(kw_text, site_name="", gender="male"):
    combined = (kw_text + " " + site_name).lower()
    rules = MALE_CATEGORY_RULES if gender == "male" else FEMALE_CATEGORY_RULES
    for cr in rules:
        for pat in cr["patterns"]:
            if pat.lower() in combined:
                return cr["category"]
    return "その他・生活諸分野"

paren_pat = re.compile(r"[\(（](\d+)[\)）]")

def api_request(url, method="GET", data=None):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json; charset=utf-8"
    }
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

for gender, cfg in SPREADSHEETS.items():
    sheet_id = cfg["id"]
    title = cfg["title"]
    kw_start_col = cfg["kw_start_col"]
    tab_name = "カテゴリ別集計"

    print(f"\n=======================================================")
    print(f"Processing: {title} ({gender})")
    print(f"=======================================================")

    # 1. Read existing '当たりKW' sheet
    escaped_range = urllib.parse.quote("'当たりKW'!A:W")
    read_url = f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}/values/{escaped_range}"
    resp = api_request(read_url)
    raw_rows = resp.get("values", [])
    if len(raw_rows) <= 1:
        print("No data in sheet.")
        continue

    data_rows = raw_rows[1:]
    categorized = {}
    all_kws = []

    for r_idx, r in enumerate(data_rows):
        row_num = r_idx + 2
        site_name = r[1] if len(r) > 1 else ""
        url = r[3] if len(r) > 3 else ""
        da = r[4] if len(r) > 4 else ""

        for c in range(kw_start_col, len(r)):
            val = r[c] if len(r) > c else ""
            if not val or not any(s in val for s in ["☆", "★", "（", "("]):
                continue
            lines = [l.strip() for l in val.split("\n") if l.strip()]
            for line in lines:
                star_count = 0
                while star_count < len(line) and line[star_count] in ["☆", "★"]:
                    star_count += 1
                vol = 0
                clean = line[star_count:].strip()
                m = paren_pat.search(clean)
                if m:
                    vol = int(m.group(1))
                    clean = paren_pat.sub("", clean).strip()

                cat = classify_kw(clean, site_name, gender=gender)
                item = {
                    "row": row_num,
                    "site_name": site_name,
                    "url": url,
                    "da": da,
                    "keyword": clean,
                    "stars": star_count,
                    "volume": vol,
                    "formatted": line,
                    "category": cat
                }
                if cat not in categorized:
                    categorized[cat] = []
                categorized[cat].append(item)
                all_kws.append(item)

    print(f"Extracted {len(all_kws)} keywords across {len(categorized)} categories.")

    # 2. Ensure tab exists in spreadsheet
    meta = api_request(f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}")
    sheet_titles = [s["properties"]["title"] for s in meta.get("sheets", [])]
    if tab_name not in sheet_titles:
        print(f"Creating new tab '{tab_name}'...")
        batch_body = {
            "requests": [
                {
                    "addSheet": {
                        "properties": {
                            "title": tab_name
                        }
                    }
                }
            ]
        }
        api_request(f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}:batchUpdate", method="POST", data=batch_body)

    # 3. Build Table Rows
    table_rows = []
    now_str = datetime.now().strftime("%Y/%m/%d %H:%M:%S")

    # Header / Title
    table_rows.append([f"【当たりKW カテゴリ別集計・探しすぎ度 判定ダッシュボード（{title}）】", "", "", "", "", "", "", ""])
    table_rows.append([f"最終更新日時: {now_str}  |  登録当たりKW総数: {len(all_kws)} 件", "", "", "", "", "", "", ""])
    table_rows.append(["", "", "", "", "", "", "", ""])

    # Summary Table Header
    table_rows.append(["カテゴリ名", "登録KW数", "構成比(シェア)", "探しすぎ判定", "☆☆☆以上", "☆☆", "☆", "今後の探索方針"])

    total_cnt = max(1, len(all_kws))
    sorted_cats = sorted(categorized.items(), key=lambda x: -len(x[1]))

    for cat, items in sorted_cats:
        cnt = len(items)
        share = round((cnt / total_cnt) * 100, 1)
        s3 = sum(1 for x in items if x["stars"] >= 3)
        s2 = sum(1 for x in items if x["stars"] == 2)
        s1 = sum(1 for x in items if x["stars"] == 1)

        if share >= 30.0:
            status = "🔴 探しすぎ（過多・飽和）"
            action = "【探索停止】他カテゴリへリソースを完全シフト"
        elif share >= 15.0:
            status = "🟡 やや多め"
            action = "【抑制】自然流入・芋づる以外は新規探索を控える"
        elif cnt >= 3:
            status = "🟢 適正水準"
            action = "【継続】水準を維持しながら並行発掘"
        else:
            status = "⚪ 不足・未開拓"
            action = "【最優先発掘】シード投入で優先的に底上げ"

        table_rows.append([
            cat,
            cnt,
            f"{share}%",
            status,
            s3,
            s2,
            s1,
            action
        ])

    # Spacer
    table_rows.append(["", "", "", "", "", "", "", ""])
    table_rows.append(["", "", "", "", "", "", "", ""])
    table_rows.append([f"【カテゴリ別 当たりキーワード詳細一覧（{title}）】", "", "", "", "", "", "", ""])
    table_rows.append(["カテゴリ", "サイト名", "実測DA", "星数", "当たりキーワード", "月間検索ボリューム", "URL", "元シート行"])

    for cat, items in sorted_cats:
        # Sort items within category by stars DESC, volume DESC
        sorted_items = sorted(items, key=lambda x: (-x["stars"], -x["volume"]))
        for item in sorted_items:
            table_rows.append([
                cat,
                item["site_name"],
                item["da"],
                "☆" * item["stars"],
                item["keyword"],
                item["volume"],
                item["url"],
                f"Row {item['row']}"
            ])

    # 4. Clear and Write
    escaped_tab = urllib.parse.quote(f"'{tab_name}'!A:H")
    clear_url = f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}/values/{escaped_tab}:clear"
    api_request(clear_url, method="POST", data={})

    write_range = urllib.parse.quote(f"'{tab_name}'!A1")
    write_url = f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}/values/{write_range}?valueInputOption=USER_ENTERED"
    write_body = {
        "range": f"'{tab_name}'!A1",
        "majorDimension": "ROWS",
        "values": table_rows
    }
    res = api_request(write_url, method="PUT", data=write_body)
    print(f"Successfully written {res.get('updatedRows')} rows to '{tab_name}' in {title}!")

print("\nDone! Both spreadsheets now have live 'カテゴリ別集計' tabs.")
