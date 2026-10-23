<#
.SYNOPSIS
    tools/research_normalize_candidates.ps1
    Responsibility: Clean, normalize and deduplicate candidate keywords against existing spreadsheet entries.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string[]]$RawKeywords = @(),

    [Parameter(Mandatory=$false)]
    [string]$InputFilePath = "",

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
. "$PSScriptRoot\..\workflow\scripts\research_seed_suggest.ps1"

$profile = Resolve-SheetProfile -SpreadsheetId $SpreadsheetId -Gender $Gender
$SpreadsheetId = $profile.SpreadsheetId

# 1. Read existing spreadsheet keywords
$data = Read-SheetData -SheetId $SpreadsheetId -TargetSheetName $SheetName
$existing = @()
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
                if ($t.StartsWith($starChar)) { $existing += $t }
            }
        }
    }
}

# 2. Gather raw inputs
$inputs = @($RawKeywords)
if (-not [string]::IsNullOrWhiteSpace($InputFilePath) -and (Test-Path $InputFilePath)) {
    $fileText = [System.IO.File]::ReadAllText($InputFilePath, [System.Text.Encoding]::UTF8)
    if ($InputFilePath.EndsWith(".json")) {
        $parsed = $fileText | ConvertFrom-Json
        if ($parsed -is [array]) { $inputs += $parsed }
        elseif ($parsed.keywords) { $inputs += $parsed.keywords }
    } else {
        $inputs += ($fileText -split "`r?`n")
    }
}

if ($inputs.Count -eq 0) {
    throw "No input keywords provided. Pass via -RawKeywords or -InputFilePath."
}

# 3. Normalize & Deduplicate
$res = Get-NormalizedCandidates -Keywords $inputs -Excludes $existing

[PSCustomObject]@{
    TotalInput = $inputs.Count
    ExistingExcluded = $existing.Count
    NewCandidatesCount = $res.TotalCandidates
    CandidateKeywords = $res.CandidateKeywords
} | ConvertTo-Json -Depth 5
