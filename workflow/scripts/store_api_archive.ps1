<#
.SYNOPSIS
    workflow/scripts/store_api_archive.ps1
    Responsibility: Safely archive raw Ubersuggest API responses directly to SQLite database (research.db)
                    in table raw_api_archive, while maintaining api_call_logs, serp_cache, and serp_entries.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\db_sqlite_manager.ps1"
. "$PSScriptRoot\eval_weak_competitor_male_rule.ps1"

function Escape-SqlParam([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return "" }
    return $s.Replace("'", "''")
}

function Save-ApiArchive {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Endpoint,

        [Parameter(Mandatory=$true)]
        [string]$TargetKey,

        [Parameter(Mandatory=$true)]
        $ResponseData,

        [Parameter(Mandatory=$false)]
        [string]$DateString = "",

        [Parameter(Mandatory=$false)]
        [string]$ArchiveBaseDir = "",

        [Parameter(Mandatory=$false)]
        [switch]$WriteJsonFile = $false
    )

    if ([string]::IsNullOrWhiteSpace($DateString)) {
        $DateString = (Get-Date).ToString("yyyy-MM-dd")
    }

    $ts = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")

    # Serialize response to JSON string
    $jsonContent = ""
    $parsedObj = $null

    if ($ResponseData -is [string]) {
        $jsonContent = $ResponseData
        try {
            $parsedObj = $ResponseData | ConvertFrom-Json
        } catch {}
    } else {
        $parsedObj = $ResponseData
        $jsonContent = $ResponseData | ConvertTo-Json -Depth 10 -Compress
    }

    # 1. Save directly to SQLite research.db (raw_api_archive table)
    $dbPath = Initialize-ResearchDatabase

    $escEndpoint = Escape-SqlParam $Endpoint
    $escKey = Escape-SqlParam $TargetKey
    $escJson = Escape-SqlParam $jsonContent
    $escDate = Escape-SqlParam $DateString

    $sqlBatch = New-Object System.Collections.Generic.List[string]
    $sqlBatch.Add("BEGIN TRANSACTION;")

    # 1.1 Insert or Replace into raw_api_archive
    $sqlBatch.Add("INSERT OR REPLACE INTO raw_api_archive (endpoint, target_key, date_string, response_json, created_at) VALUES ('$escEndpoint', '$escKey', '$escDate', '$escJson', '$ts');")

    # 1.2 Insert into api_call_logs
    $sqlBatch.Add("INSERT INTO api_call_logs (timestamp, window_date, endpoint, target_key, raw_json_path) VALUES ('$ts', '$escDate', '$escEndpoint', '$escKey', 'sqlite:raw_api_archive');")

    # 1.3 If serp_analysis, update serp_cache
    if ($Endpoint -eq "serp_analysis") {
        $sqlBatch.Add("INSERT OR REPLACE INTO serp_cache (keyword, search_date, raw_json_path) VALUES ('$escKey', '$escDate', 'sqlite:raw_api_archive');")
    }

    $sqlBatch.Add("COMMIT;")
    Invoke-SqliteNonQuery -SqlScript ([string]::Join("`n", $sqlBatch)) -DbPath $dbPath | Out-Null

    # 1.4 If serp_analysis, parse and insert serp_entries & discovered_sites
    if ($Endpoint -eq "serp_analysis" -and $null -ne $parsedObj) {
        try {
            $serpRows = Invoke-SqliteQuery -SqlQuery "SELECT id FROM serp_cache WHERE keyword = '$escKey' AND search_date = '$escDate' LIMIT 1;" -DbPath $dbPath
            if ($serpRows -and $serpRows.Count -gt 0) {
                $serpId = [int]$serpRows[0].id
                $entries = $parsedObj.serpEntries
                if (-not $entries -and $parsedObj.result -and $parsedObj.result.serp_table) {
                    $entries = $parsedObj.result.serp_table
                }

                if ($entries -and $entries.Count -gt 0) {
                    $entryBatch = New-Object System.Collections.Generic.List[string]
                    $entryBatch.Add("BEGIN TRANSACTION;")
                    $entryBatch.Add("DELETE FROM serp_entries WHERE serp_id = $serpId;")

                    $pos = 1
                    foreach ($e in $entries) {
                        $pNum = if ($null -ne $e.position) { [int]$e.position } else { $pos }
                        $dom = [string]$e.domain
                        $u = [string]$e.url
                        if ([string]::IsNullOrWhiteSpace($dom) -and -not [string]::IsNullOrWhiteSpace($u)) {
                            try { $dom = ([System.Uri]$u).Host.ToLower() } catch {}
                        }
                        $da = 0
                        if ($null -ne $e.domainAuthority) { $da = [int]$e.domainAuthority }
                        elseif ($null -ne $e.domain_authority) { $da = [int]$e.domain_authority }

                        $clicks = 0
                        if ($null -ne $e.clicks) { $clicks = [int]$e.clicks }

                        $isUgc = 0
                        $isPureLow = 0
                        if (-not [string]::IsNullOrWhiteSpace($dom)) {
                            $ugcTest = Test-WeakCompetitorMale -Domain $dom -Url $u
                            if ($ugcTest.IsWeakCompetitor) {
                                $isUgc = 1
                            } elseif ($da -ge 1 -and $da -le 9) {
                                $isPureLow = 1
                            }
                        }

                        $escDom = Escape-SqlParam $dom
                        $escU = Escape-SqlParam $u
                        $escK = Escape-SqlParam $TargetKey

                        $entryBatch.Add("INSERT INTO serp_entries (serp_id, keyword, position, domain, url, domain_authority, is_weak_ugc, is_pure_low_da, clicks) VALUES ($serpId, '$escK', $pNum, '$escDom', '$escU', $da, $isUgc, $isPureLow, $clicks);")

                        # If pure low DA personal blog, record to discovered_sites
                        if ($isPureLow -eq 1 -and -not [string]::IsNullOrWhiteSpace($dom)) {
                            $entryBatch.Add("INSERT OR IGNORE INTO discovered_sites (domain, url, da, site_type, status, discovered_from_kw) VALUES ('$escDom', '$escU', $da, 'personal_blog', 'candidate', '$escK');")
                        }
                        $pos++
                    }
                    $entryBatch.Add("COMMIT;")
                    Invoke-SqliteNonQuery -SqlScript ([string]::Join("`n", $entryBatch)) -DbPath $dbPath | Out-Null
                }
            }
        } catch {}
    }

    # 2. Optional: write to JSON file only if explicitly requested
    $targetFilePath = ""
    if ($WriteJsonFile) {
        if ([string]::IsNullOrWhiteSpace($ArchiveBaseDir)) {
            $ArchiveBaseDir = Join-Path $PSScriptRoot "..\data\raw_api_archive"
        }
        $dayDir = Join-Path $ArchiveBaseDir $DateString
        if (-not (Test-Path $dayDir)) {
            New-Item -ItemType Directory -Path $dayDir -Force | Out-Null
        }
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        $safeKey = $TargetKey
        foreach ($c in $invalidChars) {
            $safeKey = $safeKey.Replace($c, '_')
        }
        $safeKey = $safeKey.Replace(' ', '_').Replace('/', '_').Replace('\', '_')
        $fileName = "$($Endpoint)_$($safeKey).json"
        $targetFilePath = Join-Path $dayDir $fileName
        [System.IO.File]::WriteAllText($targetFilePath, $jsonContent, [System.Text.Encoding]::UTF8)
    }

    return [PSCustomObject]@{
        Saved = $true
        Date = $DateString
        Endpoint = $Endpoint
        TargetKey = $TargetKey
        FilePath = if (-not [string]::IsNullOrWhiteSpace($targetFilePath)) { $targetFilePath } else { "sqlite:raw_api_archive" }
        RelativePath = "$DateString/$Endpoint`_$TargetKey"
    }
}
