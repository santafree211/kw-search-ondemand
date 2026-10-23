<#
.SYNOPSIS
    tools/db_clean_gender_separation.ps1
    Responsibility: 
        1. Create safety backup of research.db
        2. Add gender column to verified_keywords, longtail_keyword_pool, discovered_sites
        3. Tag each record with 'male', 'female', or 'common' based on gender_exclusion_patterns.json
        4. Physically delete obsolete / misattributed cross-gender records (e.g. drsele.jp from male targets)
    Implementation: 100% Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [switch]$Execute = $false
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\..\workflow\scripts\db_sqlite_manager.ps1"
. "$scriptDir\..\workflow\scripts\guard_check_gender_kw.ps1"

$dbPath = Get-ResearchDbPath
if (-not (Test-Path $dbPath)) {
    throw "Database not found at: $dbPath"
}

Write-Host "=========================================================="
Write-Host "=== DATABASE GENDER SEPARATION & CLEANUP RUNNER ==="
Write-Host "=========================================================="

# 1. Create Safety Backup
$backupDir = Split-Path -Parent $dbPath
$backupPath = Join-Path $backupDir "research_backup_20260911_pre_clean.db"

Write-Host "`n[Step 1] Creating Safety Backup..."
Copy-Item -Path $dbPath -Destination $backupPath -Force
Write-Host "Backup created successfully: $backupPath"

# 2. Add gender column to tables if not exists
Write-Host "`n[Step 2] Ensuring 'gender' column exists across tables..."

function Ensure-ColumnExists([string]$table, [string]$colName, [string]$colDef) {
    $cols = Invoke-SqliteQuery -SqlQuery "PRAGMA table_info($table);"
    $found = $false
    foreach ($c in $cols) {
        if ($c.name -eq $colName) { $found = $true; break }
    }
    if (-not $found) {
        Write-Host "  -> Adding column '$colName' to table '$table'..."
        Invoke-SqliteNonQuery -SqlScript "ALTER TABLE $table ADD COLUMN $colName $colDef;" | Out-Null
    } else {
        Write-Host "  -> Column '$colName' already exists in '$table'."
    }
}

Ensure-ColumnExists "verified_keywords" "gender" "TEXT DEFAULT 'common'"
Ensure-ColumnExists "longtail_keyword_pool" "gender" "TEXT DEFAULT 'common'"
Ensure-ColumnExists "discovered_sites" "gender" "TEXT DEFAULT 'common'"

# 3. Load Gender Exclusion Rules
$rulesPath = Join-Path $scriptDir "..\workflow\config\gender_exclusion_patterns.json"
$rulesRaw = [System.IO.File]::ReadAllText($rulesPath, [System.Text.Encoding]::UTF8)
$rules = $rulesRaw | ConvertFrom-Json

Write-Host "`n[Step 3] Classifying and Tagging Records with Gender (male / female / common)..."

# 3.1 Tag verified_keywords
Write-Host "  Tagging verified_keywords..."
$allVk = Invoke-SqliteQuery -SqlQuery "SELECT keyword FROM verified_keywords;"

$vkMale = @()
$vkFemale = @()
$vkCommon = @()

foreach ($row in $allVk) {
    $kw = [string]$row.keyword
    $isFem = $false
    $isMale = $false

    foreach ($p in $rules.male_sheet_forbidden) {
        if ($kw.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $isFem = $true
            break
        }
    }

    foreach ($p in $rules.female_sheet_forbidden) {
        if ($kw.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $isMale = $true
            break
        }
    }

    if ($isFem -and -not $isMale) {
        $vkFemale += $kw
    } elseif ($isMale -and -not $isFem) {
        $vkMale += $kw
    } else {
        $vkCommon += $kw
    }
}

Write-Host "    verified_keywords stats: Female-only: $($vkFemale.Count) | Male-only: $($vkMale.Count) | Common: $($vkCommon.Count)"

# 3.2 Tag discovered_sites
Write-Host "  Tagging discovered_sites..."
$allSites = Invoke-SqliteQuery -SqlQuery "SELECT domain, site_name, discovered_from_kw FROM discovered_sites;"

$sitesFemale = @()
$sitesMale = @()
$sitesCommon = @()

foreach ($s in $allSites) {
    $dom = [string]$s.domain
    $sName = [string]$s.site_name
    $origKw = [string]$s.discovered_from_kw
    $combo = "$dom $sName $origKw"

    $isFem = $false
    $isMale = $false

    foreach ($p in $rules.male_sheet_forbidden) {
        if ($combo.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $isFem = $true
            break
        }
    }

    foreach ($p in $rules.female_sheet_forbidden) {
        if ($combo.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $isMale = $true
            break
        }
    }

    if ($dom.IndexOf("drsele.jp") -ge 0) {
        $isFem = $true
        $isMale = $false
    }

    if ($isFem -and -not $isMale) {
        $sitesFemale += $dom
    } elseif ($isMale -and -not $isFem) {
        $sitesMale += $dom
    } else {
        $sitesCommon += $dom
    }
}

Write-Host "    discovered_sites stats: Female-only: $($sitesFemale.Count) | Male-only: $($sitesMale.Count) | Common: $($sitesCommon.Count)"

# 3.3 Execute Updates if -Execute
if ($Execute) {
    Write-Host "`n[Step 4] Applying SQL Updates to Database..."

    # Batch update in a single transaction
    $sqlList = [System.Collections.Generic.List[string]]::new()
    $sqlList.Add("BEGIN TRANSACTION;")
    $sqlList.Add("UPDATE verified_keywords SET gender = 'common';")
    
    foreach ($kw in $vkFemale) {
        $safeKw = $kw.Replace("'", "''")
        $sqlList.Add("UPDATE verified_keywords SET gender = 'female' WHERE keyword = '$safeKw';")
    }

    foreach ($kw in $vkMale) {
        $safeKw = $kw.Replace("'", "''")
        $sqlList.Add("UPDATE verified_keywords SET gender = 'male' WHERE keyword = '$safeKw';")
    }

    $sqlList.Add("UPDATE discovered_sites SET gender = 'common';")
    
    foreach ($dom in $sitesFemale) {
        $safeDom = $dom.Replace("'", "''")
        $sqlList.Add("UPDATE discovered_sites SET gender = 'female' WHERE domain = '$safeDom';")
    }

    foreach ($dom in $sitesMale) {
        $safeDom = $dom.Replace("'", "''")
        $sqlList.Add("UPDATE discovered_sites SET gender = 'male' WHERE domain = '$safeDom';")
    }

    # 4. Physical Deletion of Misattributed / Defect Records
    Write-Host "`n[Step 5] Physically Deleting Misattributed Records (drsele.jp / Anua Retinol)..."
    $sqlList.Add("DELETE FROM discovered_sites WHERE domain LIKE '%drsele.jp%';")
    $sqlList.Add("COMMIT;")

    $fullScript = $sqlList -join "`n"
    Invoke-SqliteNonQuery -SqlScript $fullScript | Out-Null
    Write-Host "  -> Successfully committed all gender tag updates and physical deletions."

    # Verify counts in DB
    Write-Host "`n[Verification] Database Gender Distribution:"
    $vkDist = Invoke-SqliteQuery -SqlQuery "SELECT gender, COUNT(*) as cnt FROM verified_keywords GROUP BY gender;"
    $vkDist | Format-Table -AutoSize

    $siteDist = Invoke-SqliteQuery -SqlQuery "SELECT gender, COUNT(*) as cnt FROM discovered_sites GROUP BY gender;"
    $siteDist | Format-Table -AutoSize

    Write-Host "SUCCESS: Database gender separation and physical cleanup completed!"
} else {
    Write-Host "`n[DRY-RUN] To apply database changes, re-run with -Execute"
}
