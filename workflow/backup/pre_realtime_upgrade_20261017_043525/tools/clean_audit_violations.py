import json
import urllib.request
import re

TOKEN_CMD_OUTPUT = "" # We will get token dynamically

def get_token():
    import subprocess
    res = subprocess.run(["powershell", "-ExecutionPolicy", "Bypass", "-File", "tools\\sheet_get_token.ps1"], capture_output=True, text=True)
    for line in res.stdout.splitlines():
        if "ya29." in line:
            # extract string between quotes
            m = re.search(r'"(ya29\.[^"]+)"', line)
            if m:
                return m.group(1)
    # try json parse
    data = json.loads(res.stdout)
    return data["AccessToken"]

def read_sheet(sheet_id, sheet_name, token):
    url = f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}/values/'{urllib.parse.quote(sheet_name)}'!A1:Y100"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode('utf-8'))

def clear_sheet(sheet_id, sheet_name, clear_range, token):
    url = f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}/values/'{urllib.parse.quote(sheet_name)}'!{urllib.parse.quote(clear_range)}:clear"
    req = urllib.request.Request(url, method="POST", headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode('utf-8'))

def update_sheet(sheet_id, sheet_name, rows, token):
    url = f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}/values/'{urllib.parse.quote(sheet_name)}'!A1?valueInputOption=USER_ENTERED"
    body = json.dumps({
        "range": f"'{sheet_name}'!A1",
        "majorDimension": "ROWS",
        "values": rows
    }).encode('utf-8')
    req = urllib.request.Request(url, data=body, method="PUT", headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json; charset=utf-8"
    })
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode('utf-8'))

def compute_summary(row):
    stars = []
    for c in range(6, min(len(row), 22)):
        val = str(row[c]).strip()
        if not val:
            continue
        m = re.match(r'^([☆⭐★]+)', val)
        if m:
            stars.append(len(m.group(1)))
    if not stars:
        return ""
    min_s = min(stars)
    max_s = max(stars)
    if min_s == max_s:
        return f"{'⭐' * min_s} ({min_s})"
    else:
        return f"{'⭐' * min_s}〜{'⭐' * max_s}"

def main():
    token = get_token()
    print("Obtained token successfully.")

    # 1. FEMALE CLEANUP
    female_id = "1qzhyI8HYRsTyPTyaK7Xnka7PlKAuc3UxpPEaJXj1qTw"
    female_sheet = "当たりKW"
    f_data = read_sheet(female_id, female_sheet, token)
    f_values = f_data.get("values", [])
    f_header = f_values[0]
    f_rows = f_values[1:]
    print(f"Female original rows: {len(f_rows)}")

    new_f_rows = []
    for i, r in enumerate(f_rows):
        row_num = i + 2 # 1-based index in sheet
        site = r[3] if len(r) > 3 else ""

        # Row 26: Drop (履歴書 セリア - 0 seats on Google)
        if row_num == 26:
            print(f"Female: Dropping Row 26 ({site})")
            continue

        # Row 6: 自己肯定感 低い -> change to 1 star (☆)
        if row_num == 6:
            for c in range(6, len(r)):
                if "自己肯定感" in r[c] and "低い" in r[c]:
                    r[c] = re.sub(r'^[☆⭐★]+', '☆', r[c])
                    print(f"Female: Fixed Row 6 star to 1 star: {r[c]}")

        # Row 29: シルク 洗濯 -> change to 2 stars (☆☆)
        if row_num == 29:
            for c in range(6, len(r)):
                if "シルク" in r[c] and "洗濯" in r[c]:
                    r[c] = re.sub(r'^[☆⭐★]+', '☆☆', r[c])
                    print(f"Female: Fixed Row 29 star to 2 stars: {r[c]}")

        # Row 30: ゼッケン ダイソー -> change to 3 stars (☆☆☆)
        if row_num == 30:
            for c in range(6, len(r)):
                if "ゼッケン" in r[c] and "ダイソー" in r[c]:
                    r[c] = re.sub(r'^[☆⭐★]+', '☆☆☆', r[c])
                    print(f"Female: Fixed Row 30 star to 3 stars: {r[c]}")

        # Row 34: remove duplicate 'お風呂 鏡'
        if row_num == 34:
            clean_cells = r[:6]
            for c in range(6, min(len(r), 22)):
                val = str(r[c])
                if "お風呂" in val and "鏡" in val:
                    print(f"Female: Removed duplicate 'お風呂 鏡' from Row 34")
                else:
                    clean_cells.append(val)
            r = clean_cells

        # Row 36: remove duplicate 'ナイトブラ効果'
        if row_num == 36:
            clean_cells = r[:6]
            for c in range(6, min(len(r), 22)):
                val = str(r[c])
                if "ナイトブラ" in val:
                    print(f"Female: Removed duplicate 'ナイトブラ効果' from Row 36")
                else:
                    clean_cells.append(val)
            r = clean_cells

        # Row 37: remove duplicate 'シルク 洗濯'
        if row_num == 37:
            clean_cells = r[:6]
            for c in range(6, min(len(r), 22)):
                val = str(r[c])
                if "シルク" in val and "洗濯" in val:
                    print(f"Female: Removed duplicate 'シルク 洗濯' from Row 37")
                else:
                    clean_cells.append(val)
            r = clean_cells

        # Recompute summary in Col 22 (W column)
        summary = compute_summary(r)
        while len(r) <= 22:
            r.append("")
        r[22] = summary
        new_f_rows.append(r)

    print(f"Female cleaned rows count: {len(new_f_rows)}")
    clear_sheet(female_id, female_sheet, "A2:Y100", token)
    update_sheet(female_id, female_sheet, [f_header] + new_f_rows, token)
    print("Female sheet updated successfully.")

    # 2. MALE CLEANUP
    male_id = "1ZFYMVVc10cZISofcB71x6ICt9ejZyGLzmVgpKbXvR40"
    male_sheet = "当たりKW"
    m_data = read_sheet(male_id, male_sheet, token)
    m_values = m_data.get("values", [])
    m_header = m_values[0]
    m_rows = m_values[1:]
    print(f"Male original rows: {len(m_rows)}")

    new_m_rows = []
    for i, r in enumerate(m_rows):
        row_num = i + 2
        site = r[3] if len(r) > 3 else ""

        # Row 20: 履歴書 セリア -> Drop (0 seats on Google)
        if row_num == 20:
            print(f"Male: Dropping Row 20 ({site})")
            continue

        # Row 42: GOLF SHOP WILL -> Drop (0 seats on Google)
        if row_num == 42:
            print(f"Male: Dropping Row 42 ({site})")
            continue

        # Row 14: remove duplicate '光熱費平均一人暮らし' (already at Row 9)
        if row_num == 14:
            clean_cells = r[:6]
            for c in range(6, min(len(r), 22)):
                val = str(r[c])
                if "光熱費" in val:
                    print(f"Male: Removed duplicate '光熱費' from Row 14")
                else:
                    clean_cells.append(val)
            r = clean_cells

        # Row 26: remove duplicate '家系ラーメン クックら' (already at Row 17)
        if row_num == 26:
            clean_cells = r[:6]
            for c in range(6, min(len(r), 22)):
                val = str(r[c])
                if "クックら" in val:
                    print(f"Male: Removed duplicate '家系ラーメン クックら' from Row 26")
                else:
                    clean_cells.append(val)
            r = clean_cells

        # Row 37: remove duplicate 'ステーキ リベラ' (already at Row 18)
        if row_num == 37:
            clean_cells = r[:6]
            for c in range(6, min(len(r), 22)):
                val = str(r[c])
                if "リベラ" in val:
                    print(f"Male: Removed duplicate 'ステーキ リベラ' from Row 37")
                else:
                    clean_cells.append(val)
            r = clean_cells

        # Row 41: remove duplicate '祖母山北谷登山口' (already at Row 19)
        if row_num == 41:
            clean_cells = r[:6]
            for c in range(6, min(len(r), 22)):
                val = str(r[c])
                if "祖母山" in val:
                    print(f"Male: Removed duplicate '祖母山北谷登山口' from Row 41")
                else:
                    clean_cells.append(val)
            r = clean_cells

        # Check if any KWs remain
        kw_count = sum(1 for c in range(6, min(len(r), 22)) if str(r[c]).strip())
        if kw_count == 0:
            print(f"Male: Row {row_num} ({site}) has 0 KWs left, dropping.")
            continue

        new_m_rows.append(r)

    # Calculate Male Stars
    def count_male_stars(rows):
        s3, s2, s1 = 0, 0, 0
        for r in rows:
            for c in range(6, min(len(r), 22)):
                val = str(r[c]).strip()
                m = re.match(r'^([☆⭐★]+)', val)
                if m:
                    l = len(m.group(1))
                    if l >= 3: s3 += 1
                    elif l == 2: s2 += 1
                    elif l == 1: s1 += 1
        return s3, s2, s1

    s3, s2, s1 = count_male_stars(new_m_rows)
    print(f"Male Stars after deduplication: Star3+={s3}, Star2={s2}, Star1={s1}")

    # Golden Ratio for Male:
    # Star2 = 12. Star1 cannot exceed Star2 + 1 (=13) and cannot exceed s3 // 2 (=15).
    # If s1 > 13, trim excess single Star1 rows to satisfy 50:25:25 (diff <= 1).
    target_s1 = min(s2 + 1, s3 // 2)
    if s1 > target_s1:
        excess = s1 - target_s1
        print(f"Need to prune {excess} Star1 items to achieve Golden Ratio balance (Target Star1: {target_s1}).")
        
        pruned = 0
        filtered_m_rows = []
        # Prune from the bottom rows that only have a single Star1 KW
        for r in reversed(new_m_rows):
            r_kws = [str(r[c]).strip() for c in range(6, min(len(r), 22)) if str(r[c]).strip()]
            is_pure_s1 = len(r_kws) == 1 and bool(re.match(r'^[☆⭐★]{1}[^☆⭐★]', r_kws[0]))
            if pruned < excess and is_pure_s1:
                site = r[3] if len(r) > 3 else ""
                print(f"Pruning pure Star1 Male row: {site} ({r_kws[0]})")
                pruned += 1
                continue
            filtered_m_rows.append(r)
        new_m_rows = list(reversed(filtered_m_rows))

    s3, s2, s1 = count_male_stars(new_m_rows)
    tot = s3 + s2 + s1
    pct3 = round((s3 / tot) * 100, 1)
    pct2 = round((s2 / tot) * 100, 1)
    pct1 = round((s1 / tot) * 100, 1)
    print(f"Male Final Balance: Star3+={s3} ({pct3}%), Star2={s2} ({pct2}%), Star1={s1} ({pct1}%), Diff={abs(s2 - s1)}")

    # Update summary in Col 22
    for r in new_m_rows:
        summary = compute_summary(r)
        while len(r) <= 22:
            r.append("")
        r[22] = summary

    print(f"Male cleaned rows count: {len(new_m_rows)}")
    clear_sheet(male_id, male_sheet, "A2:Y100", token)
    update_sheet(male_id, male_sheet, [m_header] + new_m_rows, token)
    print("Male sheet updated successfully.")

if __name__ == "__main__":
    main()
