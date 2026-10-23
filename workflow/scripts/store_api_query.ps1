<#
.SYNOPSIS
    workflow/scripts/store_api_query.ps1
    Responsibility: Query and load archived raw API responses by Keyword/TargetKey and Date
                    directly from SQLite database (raw_api_archive), with fallback to filesystem.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\db_sqlite_manager.ps1"

function Find-ApiArchive {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Endpoint,

        [Parameter(Mandatory=$true)]
        [string]$TargetKey,

        [Parameter(Mandatory=$false)]
        [string]$DateString = "",

        [Parameter(Mandatory=$false)]
        [string]$ArchiveBaseDir = "",

        [Parameter(Mandatory=$false)]
        [string]$DbPath = ""
    )

    # 1. First Priority: Query SQLite research.db (raw_api_archive table)
    try {
        if ([string]::IsNullOrWhiteSpace($DbPath)) {
            $DbPath = Get-ResearchDbPath
        }

        if (Test-Path $DbPath) {
            $escEndpoint = $Endpoint.Replace("'", "''")
            $cleanKey = $TargetKey.Trim('"', "'", " ")
            $quotedKey = '"' + $cleanKey + '"'
            $escKey = $TargetKey.Replace("'", "''")
            $escClean = $cleanKey.Replace("'", "''")
            $escQuoted = $quotedKey.Replace("'", "''")

            $keyFilter = "(target_key = '$escKey' OR target_key = '$escClean' OR target_key = '$escQuoted')"

            $sql = ""
            if (-not [string]::IsNullOrWhiteSpace($DateString)) {
                $escDate = $DateString.Replace("'", "''")
                $sql = "SELECT endpoint, target_key, date_string, response_json FROM raw_api_archive WHERE endpoint = '$escEndpoint' AND $keyFilter AND date_string = '$escDate' LIMIT 1;"
            } else {
                $sql = "SELECT endpoint, target_key, date_string, response_json FROM raw_api_archive WHERE endpoint = '$escEndpoint' AND $keyFilter ORDER BY date_string DESC LIMIT 1;"
            }

            $rows = @(Invoke-SqliteQuery -SqlQuery $sql -DbPath $DbPath)
            if ($rows.Count -eq 0 -and ($Endpoint -eq "serp_analysis" -or $Endpoint -eq "keyword_overview")) {
                $noSpace = $cleanKey.Replace(" ", "").Replace("　", "").Replace("'", "''")
                if (-not [string]::IsNullOrWhiteSpace($noSpace)) {
                    $sqlCollapsed = "SELECT endpoint, target_key, date_string, response_json FROM raw_api_archive WHERE endpoint = '$escEndpoint' AND REPLACE(REPLACE(REPLACE(target_key, ' ', ''), '`"', ''), char(12288), '') = '$noSpace' ORDER BY date_string DESC LIMIT 1;"
                    $rows = @(Invoke-SqliteQuery -SqlQuery $sqlCollapsed -DbPath $DbPath)
                }
            }

            if ($rows.Count -gt 0) {
                $row = $rows[0]
                $parsed = $row.response_json | ConvertFrom-Json
                return [PSCustomObject]@{
                    Found = $true
                    Date = [string]$row.date_string
                    Endpoint = [string]$row.endpoint
                    TargetKey = [string]$row.target_key
                    FilePath = "sqlite:raw_api_archive"
                    Data = $parsed
                }
            }
        }
    } catch {}

    # 2. Fallback: Filesystem lookup (for legacy archives or pre-migration data)
    if ([string]::IsNullOrWhiteSpace($ArchiveBaseDir)) {
        $ArchiveBaseDir = Join-Path $PSScriptRoot "..\data\raw_api_archive"
    }

    if (-not (Test-Path $ArchiveBaseDir)) {
        return $null
    }

    # Normalize safe filename
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $safeKey = $TargetKey
    foreach ($c in $invalidChars) {
        $safeKey = $safeKey.Replace($c, '_')
    }
    $safeKey = $safeKey.Replace(' ', '_').Replace('/', '_').Replace('\', '_')
    $targetFileName = "$($Endpoint)_$($safeKey).json"

    # If DateString is specified, look in that specific date folder
    if (-not [string]::IsNullOrWhiteSpace($DateString)) {
        $specificPath = Join-Path $ArchiveBaseDir "$DateString\$targetFileName"
        if (Test-Path $specificPath) {
            $jsonText = [System.IO.File]::ReadAllText($specificPath, [System.Text.Encoding]::UTF8)
            $parsed = $jsonText | ConvertFrom-Json
            return [PSCustomObject]@{
                Found = $true
                Date = $DateString
                Endpoint = $Endpoint
                TargetKey = $TargetKey
                FilePath = $specificPath
                Data = $parsed
            }
        }
        return $null
    }

    # If DateString is not specified, search from latest date folder downwards
    $dateDirs = @(Get-ChildItem -Path $ArchiveBaseDir -Directory | Sort-Object Name -Descending)
    foreach ($d in $dateDirs) {
        $candidatePath = Join-Path $d.FullName $targetFileName
        if (Test-Path $candidatePath) {
            $jsonText = [System.IO.File]::ReadAllText($candidatePath, [System.Text.Encoding]::UTF8)
            $parsed = $jsonText | ConvertFrom-Json
            return [PSCustomObject]@{
                Found = $true
                Date = $d.Name
                Endpoint = $Endpoint
                TargetKey = $TargetKey
                FilePath = $candidatePath
                Data = $parsed
            }
        }
    }

    return $null
}
