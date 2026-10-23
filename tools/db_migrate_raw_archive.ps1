<#
.SYNOPSIS
    tools/db_migrate_raw_archive.ps1
    Responsibility: CLI tool to execute raw API archive migration into SQLite database (research.db).
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ArchiveBaseDir = "",

    [Parameter(Mandatory=$false)]
    [string]$DbPath = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\db_migrate_raw_archive.ps1"

$res = Invoke-RawArchiveMigration -ArchiveBaseDir $ArchiveBaseDir -DbPath $DbPath
$res | ConvertTo-Json -Depth 5
