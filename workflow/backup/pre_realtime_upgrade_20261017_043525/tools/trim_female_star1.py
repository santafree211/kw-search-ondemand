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

for i, r in enumerate(body):
    site = r[3] if len(r) > 3 else ''
    if 'RBD' in site or 'rbd' in site.lower():
        print(f'Found RBD at row {i+2}: {len(r)} cols')
        kws = r[6:22]
        print('Current KWs count:', len(kws))
        # Keep 4 KWs, remove 4
        new_kws = kws[:4]
        r = r[:6] + new_kws
        while len(r) <= 22:
            r.append('')
        r[22] = '⭐ (1)'
        body[i] = r

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

clear_sheet(female_id, '当たりKW', 'A2:Y100', token)
update_sheet(female_id, '当たりKW', [header] + body, token)
print('Updated female sheet with trimmed RBD gym KWs.')
