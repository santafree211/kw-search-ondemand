<#
.SYNOPSIS
    workflow/scripts/guard_serp_gate.ps1
    Responsibility: Strictly validate keyword eligibility before making serp_analysis API calls to prevent quota waste.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\research_volume_verifier.ps1"
. "$PSScriptRoot\store_api_query.ps1"
. "$PSScriptRoot\guard_check_ymyl_kw.ps1"
. "$PSScriptRoot\guard_check_entertainment_kw.ps1"

function Test-SerpEligibility {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword,

        [Parameter(Mandatory=$false)]
        [int]$MinVolume = 1900,

        [Parameter(Mandatory=$false)]
        [string]$CachePath = "",

        [Parameter(Mandatory=$false)]
        [string]$DateString = ""
    )

    $cleanKw = $Keyword.Trim()
    if ([string]::IsNullOrWhiteSpace($cleanKw)) {
        return [PSCustomObject]@{
            Eligible = $false
            Reason = "EmptyKeyword"
            Action = "Block"
            Volume = -1
        }
    }

    # 0. Check YMYL / Pharmaceutical Law Violation (Physical Block)
    $ymylCheck = Test-KeywordYmylEligibility -Keyword $cleanKw
    if ($ymylCheck.IsYmyl) {
        return [PSCustomObject]@{
            Eligible = $false
            Reason = "YmylBlocked"
            Action = "Block"
            Volume = -1
            Category = $ymylCheck.Category
            CategoryName = $ymylCheck.CategoryName
            MatchedPattern = $ymylCheck.MatchedPattern
            Message = $ymylCheck.Reason
        }
    }

    # 0.5 Check Entertainment / Fiction Violation (Physical Block)
    $entCheck = Test-KeywordEntertainmentEligibility -Keyword $cleanKw
    if ($entCheck.IsEntertainment) {
        return [PSCustomObject]@{
            Eligible = $false
            Reason = "EntertainmentBlocked"
            Action = "Block"
            Volume = -1
            Category = $entCheck.Category
            CategoryName = $entCheck.CategoryName
            MatchedPattern = $entCheck.MatchedPattern
            Message = $entCheck.Reason
        }
    }

    # 1. Check local SERP archive (Cache First)
    $cachedSerp = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $cleanKw -DateString $DateString
    if ($null -ne $cachedSerp -and $cachedSerp.Found) {
        return [PSCustomObject]@{
            Eligible = $false
            Reason = "CacheHit"
            Action = "UseLocalCache"
            Volume = -1
            CachedFilePath = $cachedSerp.FilePath
            CachedDate = $cachedSerp.Date
        }
    }

    # 2. Check verified volume threshold (>= MinVolume)
    $vol = -1
    try {
        $volCheck = Test-KeywordVolume -TargetKeyword $cleanKw -CachePath $CachePath
        if ($null -ne $volCheck) {
            if ($null -ne $volCheck.SearchVolume) { $vol = [int]$volCheck.SearchVolume }
            elseif ($null -ne $volCheck.Volume) { $vol = [int]$volCheck.Volume }
        }
    } catch {
        return [PSCustomObject]@{
            Eligible = $false
            Reason = "VolumeNotVerified"
            Action = "Block"
            Volume = -1
            MinRequired = $MinVolume
            Error = $_.Exception.Message
        }
    }

    if ($vol -lt $MinVolume) {
        return [PSCustomObject]@{
            Eligible = $false
            Reason = "VolumeBelowThreshold"
            Action = "Block"
            Volume = $vol
            MinRequired = $MinVolume
        }
    }

    # 3. Eligible for API call
    return [PSCustomObject]@{
        Eligible = $true
        Reason = "PassedVolumeGate"
        Action = "ExecuteApi"
        Volume = $vol
    }
}
