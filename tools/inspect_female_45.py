
import json, subprocess
res = subprocess.check_output(['powershell', '-ExecutionPolicy', 'Bypass', '-Command', '& { . .\\workflow\\scripts\\sheet_profile_resolver.ps1; . .\\workflow\\scripts\\sheet_data_reader.ps1;  = Resolve-SheetProfile -Gender female;  = Read-SheetData -SheetId .SpreadsheetId -TargetSheetName .TargetSheetName; .RawValues[44] | ConvertTo-Json -Compress }'])
row = json.loads(res.decode('utf-8', errors='ignore'))
for i, c in enumerate(row):
    if c:
        print(f'{i}: {c}')
