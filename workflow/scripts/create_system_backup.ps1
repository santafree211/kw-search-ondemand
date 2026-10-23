$ErrorActionPreference = "Stop"
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$bDir = Join-Path $PSScriptRoot "..\backup\pre_realtime_upgrade_$ts"
New-Item -ItemType Directory -Path $bDir -Force | Out-Null

Copy-Item -Path (Join-Path $PSScriptRoot "..\scripts") -Destination (Join-Path $bDir "scripts") -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "..\data") -Destination (Join-Path $bDir "data") -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "..\..\tools") -Destination (Join-Path $bDir "tools") -Recurse -Force

Write-Output "BACKUP_COMPLETED_SUCCESSFULLY: $bDir"
Get-ChildItem $bDir | Select-Object Name, Length
