import json, urllib.request, urllib.parse, re, subprocess

res = subprocess.run(['powershell', '-ExecutionPolicy', 'Bypass', '-File', 'tools\\sheet_get_token.ps1'], capture_output=True, text=True)
m = re.search(r'"(ya29\.[^"]+)"', res.stdout)
token = m.group(1)

female_id = '1qzhyI8HYRsTyPTyaK7Xnka7PlKAuc3UxpPEaJXj1qTw'
encoded_range = urllib.parse.quote("'当たりKW'!A1:Y100")
url = f'https://sheets.googleapis.com/v4/spreadsheets/{female_id}/values/{encoded_range}'
req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode('utf-8'))

rows = data.get('values', [])
header = rows[0]
body = rows[1:]

modified = False
for i, r in enumerate(body):
    r_str = " ".join(r)
    if "小和田" in r_str or "lerepairedelagirafe.fr" in r_str:
        print(f"Modifying Row {i+2}: removing '小和田哲男 雅子さま 親戚'")
        prefix = r[:6]
        kws = [c.strip() for c in r[6:22] if c and c.strip()]
        new_kws = [k for k in kws if "小和田" not in k]
        new_r = prefix + new_kws
        while len(new_r) < 22:
            new_r.append('')
        stars = []
        for k in new_kws:
            if k.startswith('☆☆☆☆☆'): stars.append(5)
            elif k.startswith('☆☆☆☆'): stars.append(4)
            elif k.startswith('☆☆☆'): stars.append(3)
            elif k.startswith('☆☆'): stars.append(2)
            elif k.startswith('☆'): stars.append(1)
        if stars:
            min_s, max_s = min(stars), max(stars)
            summary = f"⭐ ({min_s})" if min_s == max_s else f"⭐~{'⭐'*max_s}"
        else:
            summary = ""
        new_r.append(summary)
        new_r.append(r[23] if len(r) > 23 else "")
        new_r.append(r[24] if len(r) > 24 else "")
        body[i] = new_r
        modified = True

if modified:
    def clear_sheet(sheet_id, sheet_name, clear_range, token):
        url = f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}/values/'{urllib.parse.quote(sheet_name)}'!{urllib.parse.quote(clear_range)}:clear"
        req = urllib.request.Request(url, method="POST", headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode('utf-8'))

    def update_sheet(sheet_id, sheet_name, rows, token):
        url = f"https://sheets.googleapis.com/v4/spreadsheets/{sheet_id}/values/'{urllib.parse.quote(sheet_name)}'!A1?valueInputOption=USER_ENTERED"
        body_data = json.dumps({
            "range": f"'{sheet_name}'!A1",
            "majorDimension": "ROWS",
            "values": rows
        }).encode('utf-8')
        req = urllib.request.Request(url, data=body_data, method="PUT", headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=utf-8"
        })
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode('utf-8'))

    clear_sheet(female_id, '当たりKW', 'A2:Y100', token)
    update_sheet(female_id, '当たりKW', [header] + body, token)
    print("Updated female sheet successfully without invalid KW!")
