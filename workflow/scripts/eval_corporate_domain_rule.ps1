<#
.SYNOPSIS
    workflow/scripts/eval_corporate_domain_rule.ps1
    Responsibility: Strictly identify and filter out corporate, institutional, and high-DA authority domains.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Test-IsCorporateDomain {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain,

        [Parameter(Mandatory=$false)]
        [string]$Url = ""
    )

    $d = $Domain.ToLower().Trim()
    if ($d.StartsWith("www.")) { $d = $d.Substring(4) }

    # 1. Corporate TLD / Official Institutional Extensions (100% Corporate)
    if ($d -match "\.(?:co\.jp|ac\.jp|go\.jp|lg\.jp|or\.jp|ed\.jp)$") {
        return [PSCustomObject]@{
            IsCorporate = $true
            Reason      = "CorporateOfficialTld"
            Matched     = $matches[0]
        }
    }

    # 2. Major Enterprise Portals, EC Platforms, Aggregators, Government & Corporate Media
    $corporateRoots = @(
        # Major tech & portals
        "yahoo.co.jp", "google.com", "google.co.jp", "apple.com", "microsoft.com",
        "amazon.co.jp", "amazon.com", "rakuten.co.jp", "rakuten.ne.jp", "kakaku.com",
        "mercari.com", "paypay.ne.jp", "line.me", "wikipedia.org", "youtube.com",
        "twitter.com", "x.com", "instagram.com", "facebook.com", "tiktok.com",
        # News & Press & Business Media
        "prtimes.jp", "nikkei.com", "asahi.com", "yomiuri.co.jp", "mainichi.jp",
        "sankei.com", "toyokeizai.net", "diamond.jp", "president.jp", "itmedia.co.jp",
        "impress.co.jp", "businessinsider.jp", "forbesjapan.com", "newspicks.com",
        # Major Recruitment & Job Agencies
        "mynavi.jp", "recruit.co.jp", "doda.jp", "en-japan.com", "type.jp",
        "indeed.com", "rikunabi.com", "openwork.jp", "vorkers.com", "agent-network.com",
        # Major Telecomm & Financial
        "docomo.ne.jp", "au.com", "softbank.jp", "smbc.co.jp", "mufg.jp", "mizuhobank.co.jp",
        "rakuten-card.co.jp", "sbigroup.co.jp", "monex.co.jp", "nomura.co.jp",
        # Medical & Health Institutions
        "mhlw.go.jp", "kango-roo.com", "e-heya.net", "suumo.jp", "homes.co.jp"
    )

    foreach ($cr in $corporateRoots) {
        if ($d -eq $cr -or $d.EndsWith(".$cr")) {
            return [PSCustomObject]@{
                IsCorporate = $true
                Reason      = "KnownEnterpriseDomain"
                Matched     = $cr
            }
        }
    }

    # 3. Healthcare / Medical Clinic Corporate patterns
    if ($d -match "(?i)(?:-clinic|-hospital|medical-|\.clinic|\.hospital|\.dental)") {
        return [PSCustomObject]@{
            IsCorporate = $true
            Reason      = "MedicalInstitutionDomain"
            Matched     = $matches[0]
        }
    }

    return [PSCustomObject]@{
        IsCorporate = $false
        Reason      = "NotCorporate"
        Matched     = ""
    }
}
