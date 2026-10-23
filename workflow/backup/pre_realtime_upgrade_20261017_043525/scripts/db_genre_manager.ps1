<#
.SYNOPSIS
    workflow/scripts/db_genre_manager.ps1
    Responsibility: Manage 50 genres, balance ratios, and assign keywords/sites.
    Implementation: 100% Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\db_sqlite_manager.ps1"

function Escape-SqlParam([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return "" }
    return $s.Replace("'", "''")
}

function Initialize-GenreSchema {
    param([string]$DbPath = "")

    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Get-ResearchDbPath
    }

    # 1. Create genres table
    $schemaSql = @"
CREATE TABLE IF NOT EXISTS genres (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    category TEXT DEFAULT 'General',
    target_kw_count INTEGER DEFAULT 200,
    star3_count INTEGER DEFAULT 0,
    star2_count INTEGER DEFAULT 0,
    star1_count INTEGER DEFAULT 0,
    total_count INTEGER DEFAULT 0,
    status TEXT DEFAULT 'active'
);
CREATE INDEX IF NOT EXISTS idx_genres_name ON genres(name);
"@
    Invoke-SqliteNonQuery -SqlScript $schemaSql -DbPath $DbPath | Out-Null

    # 2. Add genre_id column to verified_keywords and discovered_sites if not exists
    $vkCols = Invoke-SqliteQuery -SqlQuery "PRAGMA table_info(verified_keywords);" -DbPath $DbPath
    $hasGenreId = $false
    foreach ($c in $vkCols) {
        if ($c.name -eq "genre_id") { $hasGenreId = $true; break }
    }
    if (-not $hasGenreId) {
        try {
            Invoke-SqliteNonQuery -SqlScript "ALTER TABLE verified_keywords ADD COLUMN genre_id INTEGER REFERENCES genres(id);" -DbPath $DbPath | Out-Null
            Invoke-SqliteNonQuery -SqlScript "CREATE INDEX IF NOT EXISTS idx_vk_genre ON verified_keywords(genre_id);" -DbPath $DbPath | Out-Null
        } catch {}
    }

    $dsCols = Invoke-SqliteQuery -SqlQuery "PRAGMA table_info(discovered_sites);" -DbPath $DbPath
    $hasDsGenreId = $false
    foreach ($c in $dsCols) {
        if ($c.name -eq "genre_id") { $hasDsGenreId = $true; break }
    }
    if (-not $hasDsGenreId) {
        try {
            Invoke-SqliteNonQuery -SqlScript "ALTER TABLE discovered_sites ADD COLUMN genre_id INTEGER REFERENCES genres(id);" -DbPath $DbPath | Out-Null
            Invoke-SqliteNonQuery -SqlScript "CREATE INDEX IF NOT EXISTS idx_ds_genre ON discovered_sites(genre_id);" -DbPath $DbPath | Out-Null
        } catch {}
    }

    $ltCols = Invoke-SqliteQuery -SqlQuery "PRAGMA table_info(longtail_keyword_pool);" -DbPath $DbPath
    $hasLtGenreId = $false
    foreach ($c in $ltCols) {
        if ($c.name -eq "genre_id") { $hasLtGenreId = $true; break }
    }
    if (-not $hasLtGenreId -and $ltCols.Count -gt 0) {
        try {
            Invoke-SqliteNonQuery -SqlScript "ALTER TABLE longtail_keyword_pool ADD COLUMN genre_id INTEGER REFERENCES genres(id);" -DbPath $DbPath | Out-Null
            Invoke-SqliteNonQuery -SqlScript "CREATE INDEX IF NOT EXISTS idx_lt_genre ON longtail_keyword_pool(genre_id);" -DbPath $DbPath | Out-Null
        } catch {}
    }

    # 3. Seed initial 30 genres from workflow/data/initial_genres.json
    $jsonPath = Join-Path $PSScriptRoot "..\data\initial_genres.json"
    if (Test-Path $jsonPath) {
        $rawText = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
        $genreList = $rawText | ConvertFrom-Json
        $sqlList = New-Object System.Collections.Generic.List[string]
        $sqlList.Add("BEGIN TRANSACTION;")
        foreach ($g in $genreList) {
            $name = Escape-SqlParam ([string]$g.name)
            $cat = Escape-SqlParam ([string]$g.category)
            $target = [int]$g.target
            $sqlList.Add("INSERT OR IGNORE INTO genres (id, name, category, target_kw_count) VALUES ($($g.id), '$name', '$cat', $target);")
        }
        $sqlList.Add("COMMIT;")
        $combined = [string]::Join("`n", $sqlList)
        Invoke-SqliteNonQuery -SqlScript $combined -DbPath $DbPath | Out-Null
    }

    $count = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM genres;" -DbPath $DbPath)[0].cnt
    return $count
}

function Register-DiscoveredGenre {
    param(
        [Parameter(Mandatory=$true)]
        [string]$GenreName,

        [Parameter(Mandatory=$false)]
        [string]$Category = "Discovered",

        [Parameter(Mandatory=$false)]
        [string]$DbPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Get-ResearchDbPath
    }

    $currentCount = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM genres;" -DbPath $DbPath)[0].cnt
    if ($currentCount -ge 50) {
        throw "Genre capacity limit reached (50 genres maximum)."
    }

    $escName = Escape-SqlParam $GenreName
    $escCat = Escape-SqlParam $Category
    $sql = "INSERT OR IGNORE INTO genres (name, category, target_kw_count) VALUES ('$escName', '$escCat', 200);"
    Invoke-SqliteNonQuery -SqlScript $sql -DbPath $DbPath | Out-Null

    $res = Invoke-SqliteQuery -SqlQuery "SELECT * FROM genres WHERE name = '$escName' LIMIT 1;" -DbPath $DbPath
    return $res[0]
}

function Auto-AssignKeywordGenres {
    param([string]$DbPath = "")

    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Get-ResearchDbPath
    }

    # Fetch all genres
    $genres = Invoke-SqliteQuery -SqlQuery "SELECT id, name FROM genres;" -DbPath $DbPath
    $genreMap = @{}
    foreach ($g in $genres) {
        $genreMap[$g.name] = [int]$g.id
    }

    # Load rules from JSON
    $rulesPath = Join-Path $PSScriptRoot "..\data\genre_rules.json"
    if (-not (Test-Path $rulesPath)) {
        return 0
    }
    $rulesRaw = [System.IO.File]::ReadAllText($rulesPath, [System.Text.Encoding]::UTF8)
    $rules = $rulesRaw | ConvertFrom-Json

    # Fetch unassigned keywords
    $kws = Invoke-SqliteQuery -SqlQuery "SELECT keyword FROM verified_keywords WHERE genre_id IS NULL OR genre_id = 0;" -DbPath $DbPath
    if ($null -eq $kws -or $kws.Count -eq 0) {
        return 0
    }

    $sqlList = New-Object System.Collections.Generic.List[string]
    $sqlList.Add("BEGIN TRANSACTION;")
    $assignedCount = 0

    foreach ($item in $kws) {
        $kw = [string]$item.keyword
        $matchedGenreId = 0

        foreach ($r in $rules) {
            $gName = [string]$r.genre_name
            if (-not $genreMap.ContainsKey($gName)) { continue }
            $gId = $genreMap[$gName]

            $isMatch = $false
            foreach ($p in $r.patterns) {
                if ($kw.IndexOf([string]$p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $isMatch = $true
                    break
                }
            }

            if ($isMatch) {
                $matchedGenreId = $gId
                break
            }
        }

        if ($matchedGenreId -gt 0) {
            $escKw = Escape-SqlParam $kw
            $sqlList.Add("UPDATE verified_keywords SET genre_id = $matchedGenreId WHERE keyword = '$escKw';")
            $assignedCount++
        }
    }

    # Also assign genres for unassigned longtail keywords
    $ltKws = Invoke-SqliteQuery -SqlQuery "SELECT keyword FROM longtail_keyword_pool WHERE genre_id IS NULL OR genre_id = 0;" -DbPath $DbPath
    if ($null -ne $ltKws -and $ltKws.Count -gt 0) {
        foreach ($item in $ltKws) {
            $kw = [string]$item.keyword
            $matchedGenreId = 0
            foreach ($r in $rules) {
                $gName = [string]$r.genre_name
                if (-not $genreMap.ContainsKey($gName)) { continue }
                $gId = $genreMap[$gName]

                $isMatch = $false
                foreach ($p in $r.patterns) {
                    if ($kw.IndexOf([string]$p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $isMatch = $true
                        break
                    }
                }
                if ($isMatch) {
                    $matchedGenreId = $gId
                    break
                }
            }
            if ($matchedGenreId -gt 0) {
                $escKw = Escape-SqlParam $kw
                $sqlList.Add("UPDATE longtail_keyword_pool SET genre_id = $matchedGenreId WHERE keyword = '$escKw';")
                $assignedCount++
            }
        }
    }

    $sqlList.Add("COMMIT;")
    if ($assignedCount -gt 0) {
        $combined = [string]::Join("`n", $sqlList)
        Invoke-SqliteNonQuery -SqlScript $combined -DbPath $DbPath | Out-Null
    }

    return $assignedCount
}

function Get-GenreProgressOverview {
    param([string]$DbPath = "")

    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Get-ResearchDbPath
    }

    $sql = @"
SELECT 
    g.id,
    g.name,
    g.category,
    g.target_kw_count as target,
    COUNT(vk.keyword) as verified_kw_count,
    ROUND((CAST(COUNT(vk.keyword) AS REAL) / g.target_kw_count) * 100, 1) as progress_pct
FROM genres g
LEFT JOIN verified_keywords vk ON g.id = vk.genre_id
GROUP BY g.id, g.name, g.category, g.target_kw_count
ORDER BY g.id ASC;
"@
    $results = Invoke-SqliteQuery -SqlQuery $sql -DbPath $DbPath
    return $results
}

function Get-NextUnderrepresentedGenreSeeds {
    param(
        [Parameter(Mandatory=$false)]
        [int]$Limit = 1,

        [Parameter(Mandatory=$false)]
        [string]$DbPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Get-ResearchDbPath
    }

    # 1. Query progress from DB ordered by count ASC
    $sql = @"
SELECT 
    g.id,
    g.name,
    g.category,
    g.target_kw_count as target,
    COUNT(vk.keyword) as verified_kw_count
FROM genres g
LEFT JOIN verified_keywords vk ON g.id = vk.genre_id
GROUP BY g.id, g.name, g.category, g.target_kw_count
ORDER BY verified_kw_count ASC, g.id ASC;
"@
    $progress = Invoke-SqliteQuery -SqlQuery $sql -DbPath $DbPath
    if ($null -eq $progress -or $progress.Count -eq 0) {
        return @()
    }

    # 2. Load seed dictionary from JSON
    $seedsFile = Join-Path $PSScriptRoot "..\data\genre_seeds.json"
    $seedMap = @{}
    if (Test-Path $seedsFile) {
        $raw = [System.IO.File]::ReadAllText($seedsFile, [System.Text.Encoding]::UTF8)
        $parsed = $raw | ConvertFrom-Json
        foreach ($item in $parsed) {
            $seedMap[[int]$item.genre_id] = $item.seeds
        }
    }

    # 3. Pick the top $Limit underrepresented genres
    $chosen = @()
    for ($i = 0; $i -lt [Math]::Min($Limit, $progress.Count); $i++) {
        $g = $progress[$i]
        $gid = [int]$g.id
        $sList = if ($seedMap.ContainsKey($gid)) { $seedMap[$gid] } else { @() }

        $chosen += [PSCustomObject]@{
            GenreId = $gid
            GenreName = $g.name
            Category = $g.category
            CurrentVerifiedCount = [int]$g.verified_kw_count
            TargetCount = [int]$g.target
            Seeds = $sList
        }
    }

    return $chosen
}