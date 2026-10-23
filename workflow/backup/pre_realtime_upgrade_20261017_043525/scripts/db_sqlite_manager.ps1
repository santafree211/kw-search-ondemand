<#
.SYNOPSIS
    db_sqlite_manager.ps1
    Responsibility: Provide unified SQLite database management and query utilities.
    Implementation: Pure ASCII with robust UTF-8 stream handling for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Get-SqliteBinaryPath {
    $binPath = Join-Path $PSScriptRoot "..\bin\sqlite3.exe"
    if (Test-Path $binPath) {
        return (Resolve-Path $binPath).Path
    }
    # Fallback to PATH
    $cmd = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    throw "sqlite3.exe not found at $binPath or in PATH."
}

function Get-ResearchDbPath {
    param([string]$CustomPath = "")
    if (-not [string]::IsNullOrWhiteSpace($CustomPath)) {
        return $CustomPath
    }
    $dbPath = Join-Path $PSScriptRoot "..\data\research.db"
    $parent = Split-Path $dbPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    return $dbPath
}

function Invoke-SqliteNonQuery {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SqlScript,

        [Parameter(Mandatory=$false)]
        [string]$DbPath = ""
    )

    $exe = Get-SqliteBinaryPath
    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Get-ResearchDbPath
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = "`"$DbPath`" -cmd `".timeout 5000`" -batch"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = [System.Diagnostics.Process]::Start($psi)
    $writer = New-Object System.IO.StreamWriter($proc.StandardInput.BaseStream, [System.Text.UTF8Encoding]::new($false))
    $writer.Write($SqlScript)
    $writer.Flush()
    $writer.Close()

    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        throw "SQLite NonQuery Error (Exit $($proc.ExitCode)): $stderr"
    }
    return $true
}

function Invoke-SqliteQuery {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SqlQuery,

        [Parameter(Mandatory=$false)]
        [string]$DbPath = ""
    )

    $exe = Get-SqliteBinaryPath
    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Get-ResearchDbPath
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = "`"$DbPath`" -cmd `".timeout 5000`" -json -batch"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = [System.Diagnostics.Process]::Start($psi)
    $writer = New-Object System.IO.StreamWriter($proc.StandardInput.BaseStream, [System.Text.UTF8Encoding]::new($false))
    $writer.Write($SqlQuery)
    $writer.Flush()
    $writer.Close()

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        throw "SQLite Query Error (Exit $($proc.ExitCode)): $stderr"
    }

    if ([string]::IsNullOrWhiteSpace($stdout) -or $stdout.Trim() -eq "" -or $stdout.Trim() -eq "[]") {
        return
    }

    try {
        $parsed = $stdout | ConvertFrom-Json
        if ($null -eq $parsed) {
            return
        }
        # Ensure only PSCustomObject rows are returned, discarding scalar outputs
        $validRows = @($parsed | Where-Object { $null -ne $_ -and $_ -is [System.Management.Automation.PSCustomObject] })
        if ($validRows.Count -eq 0) {
            return
        }
        return $validRows
    } catch {
        return
    }
}

function Initialize-ResearchDatabase {
    param(
        [Parameter(Mandatory=$false)]
        [string]$DbPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Get-ResearchDbPath
    }

    $schema = @"
-- 1. Verified Search Volume Cache (Tier 1: Qualified Vol >= 1900)
CREATE TABLE IF NOT EXISTS verified_keywords (
    keyword TEXT PRIMARY KEY,
    volume INTEGER NOT NULL,
    cpc REAL DEFAULT 0,
    seo_difficulty INTEGER DEFAULT 0,
    source TEXT DEFAULT 'ubersuggest',
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_vk_volume ON verified_keywords(volume);

-- 1B. Longtail Keyword Pool (Tier 2: Sub-1900 and Headings/Co-occurrences)
CREATE TABLE IF NOT EXISTS longtail_keyword_pool (
    keyword TEXT PRIMARY KEY,
    volume INTEGER NOT NULL,
    cpc REAL DEFAULT 0,
    seo_difficulty INTEGER DEFAULT 0,
    source TEXT DEFAULT 'ubersuggest',
    genre_id INTEGER,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_lt_volume ON longtail_keyword_pool(volume);
CREATE INDEX IF NOT EXISTS idx_lt_genre ON longtail_keyword_pool(genre_id);

-- 2. SERP Parent Cache
CREATE TABLE IF NOT EXISTS serp_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    keyword TEXT NOT NULL,
    search_date DATE NOT NULL,
    raw_json_path TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(keyword, search_date)
);
CREATE INDEX IF NOT EXISTS idx_sc_kw_date ON serp_cache(keyword, search_date);

-- 3. SERP Entries (Top 10/20)
CREATE TABLE IF NOT EXISTS serp_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    serp_id INTEGER NOT NULL REFERENCES serp_cache(id) ON DELETE CASCADE,
    keyword TEXT NOT NULL,
    position INTEGER NOT NULL,
    domain TEXT NOT NULL,
    url TEXT NOT NULL,
    domain_authority INTEGER NOT NULL,
    is_weak_ugc INTEGER DEFAULT 0,
    is_pure_low_da INTEGER DEFAULT 0,
    clicks INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_se_kw_pos ON serp_entries(keyword, position);
CREATE INDEX IF NOT EXISTS idx_se_domain ON serp_entries(domain);

-- 4. Discovered Competitor Sites (DA 1-9 Blogs)
CREATE TABLE IF NOT EXISTS discovered_sites (
    domain TEXT PRIMARY KEY,
    site_name TEXT,
    url TEXT,
    da INTEGER,
    site_type TEXT,
    gender TEXT DEFAULT 'common',
    status TEXT DEFAULT 'candidate',
    discovered_from_kw TEXT,
    discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_ds_gender_status ON discovered_sites(gender, status);

-- 5. API Real Call Logs (Audit Standard)
CREATE TABLE IF NOT EXISTS api_call_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    window_date DATE NOT NULL,
    endpoint TEXT NOT NULL,
    target_key TEXT NOT NULL,
    status_code INTEGER DEFAULT 200,
    raw_json_path TEXT
);
CREATE INDEX IF NOT EXISTS idx_acl_ts ON api_call_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_acl_window ON api_call_logs(window_date, endpoint);

-- 6. Raw API Responses Archive (Unified Storage replacing individual JSON files)
CREATE TABLE IF NOT EXISTS raw_api_archive (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    endpoint TEXT NOT NULL,
    target_key TEXT NOT NULL,
    date_string TEXT NOT NULL,
    response_json TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(endpoint, target_key, date_string)
);
CREATE INDEX IF NOT EXISTS idx_raw_archive_query ON raw_api_archive(endpoint, target_key, date_string);
CREATE INDEX IF NOT EXISTS idx_raw_archive_ep_key ON raw_api_archive(endpoint, target_key);
CREATE INDEX IF NOT EXISTS idx_raw_archive_date ON raw_api_archive(date_string);
"@

    Invoke-SqliteNonQuery -SqlScript $schema -DbPath $DbPath | Out-Null
    return $DbPath
}
