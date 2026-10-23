<#
.SYNOPSIS
    tools/portfolio_inspect_stock.ps1
    Responsibility: Inspect shelved stock keywords and calculate available addition slots for ratio 50:25:25.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$StockPath = "",

    [Parameter(Mandatory=$false)]
    [string]$SpreadsheetId = "",

    [Parameter(Mandatory=$false)]
    [string]$Gender = "",

    [Parameter(Mandatory=$false)]
    [string]$SheetName = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\sheet_profile_resolver.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_data_reader.ps1"
. "$PSScriptRoot\..\workflow\scripts\portfolio_ratio_balancer.ps1"

$profile = Resolve-SheetProfile -SpreadsheetId $SpreadsheetId -Gender $Gender
$targetSheetId = $profile.SpreadsheetId

if ([string]::IsNullOrWhiteSpace($StockPath)) {
    $StockPath = $profile.StockPath
}

# 1. Read sheet keywords
$data = Read-SheetData -SheetId $targetSheetId -TargetSheetName $SheetName
$currentKws = @()
$header = $data.Header
$kwStartCol = 6
for ($i = 0; $i -lt $header.Count; $i++) {
    $h = [string]$header[$i]
    if ($h.Contains("KW1")) {
        $kwStartCol = $i
        break
    }
}

$starChar = [char]0x2606
foreach ($r in $data.Rows) {
    for ($c = $kwStartCol; $c -lt [Math]::Min($r.Count, ($kwStartCol + 16)); $c++) {
        $val = [string]$r[$c]
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            $lines = $val -split "`r?`n"
            foreach ($l in $lines) {
                $t = $l.Trim()
                if ($t.StartsWith($starChar)) { $currentKws += $t }
            }
        }
    }
}

$c3 = @($currentKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR3_PLUS" }).Count
$c2 = @($currentKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR2" }).Count
$c1 = @($currentKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR1" }).Count

# 2. Read shelved stock
$shelved = @()
if (Test-Path $StockPath) {
    $text = [System.IO.File]::ReadAllText($StockPath, [System.Text.Encoding]::UTF8)
    $shelved = @($text | ConvertFrom-Json | ForEach-Object { $_ })
}

# 3. Calculate next allowable slots (for every 2 Star3, 1 Star2 and 1 Star1 can be added)
$allowedStar2 = [int][Math]::Floor($c3 / 2) - $c2
$allowedStar1 = [int][Math]::Floor($c3 / 2) - $c1

[PSCustomObject]@{
    TargetGender = $profile.Gender
    SheetTitle = $profile.Title
    SpreadsheetId = $targetSheetId
    CurrentTotal = $currentKws.Count
    CurrentStar3 = $c3
    CurrentStar2 = $c2
    CurrentStar1 = $c1
    ShelvedCount = $shelved.Count
    ShelvedKeywords = $shelved
    AvailableSlots = [PSCustomObject]@{
        CanAddStar3 = "Unlimited (Helps expand Star2 and Star1 capacity)"
        AllowedStar2WithoutNewStar3 = [Math]::Max(0, $allowedStar2)
        AllowedStar1WithoutNewStar3 = [Math]::Max(0, $allowedStar1)
        NextBalancedBundle = "Add 2 x Star3+ keywords to unlock 1 x Star2 and 1 x Star1"
    }
} | ConvertTo-Json -Depth 5
