import json, urllib.request, urllib.parse, re, subprocess

res = subprocess.run(['powershell', '-ExecutionPolicy', 'Bypass', '-File', 'tools\\sheet_get_token.ps1'], capture_output=True, text=True)
m = re.search(r'"(ya29\.[^"]+)"', res.stdout)
token = m.group(1)

female_id = '1qzhyI8HYRsTyPTyaK7Xnka7PlKAuc3UxpPEaJXj1qTw'
encoded_range = urllib.parse.quote("'当たりKW'!A1:Y100")
url = f"https://sheets.googleapis.com/v4/spreadsheets/{female_id}/values/{encoded_range}"
req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode('utf-8'))

rows = data.get('values', [])
print(f"Total rows in Female sheet: {len(rows)}")
for i, r in enumerate(rows[:5]):
    print(f"Row {i+1}: cols={len(r)}")
    if s1 > 0 or s2 > 0 or s3 > 0:
        print(f"Row {i:2d} ({site[:20]}): {len(kws)} KWs [s1:{s1}, s2:{s2}, s3:{s3}] -> {kws}")
