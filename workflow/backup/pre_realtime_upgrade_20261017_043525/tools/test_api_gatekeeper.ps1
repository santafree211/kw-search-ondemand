# tools/test_api_gatekeeper.ps1
# Responsibility: Automated unit test suite for Pre-flight API Gatekeeper & Auto-Archive in ubersuggest_mcp_api.ps1

$ErrorActionPreference = "Stop"

$mcpConfig = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_config.ps1"
$mcpAuth   = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_auth.ps1"
$mcpApi    = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_api.ps1"

if (-not ((Test-Path $mcpConfig) -and (Test-Path $mcpAuth) -and (Test-Path $mcpApi))) {
    throw "Ubersuggest MCP scripts not found."
}

. $mcpConfig
. $mcpAuth
. $mcpApi

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   PRE-FLIGHT API GATEKEEPER AUTOMATED TEST SUITE           " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$allPassed = $true
$testIndex = 1

function Run-GatekeeperTest([string]$testName, [string]$jsonRpcPayload, [bool]$expectHit) {
    global:testIndex
    Write-Host "`n[Test $global:testIndex] $testName" -ForegroundColor Yellow
    $global:testIndex++

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = $null
    try {
        $response = Forward-RemoteMcp $jsonRpcPayload
    } catch {
        $response = $_.Exception.Message
    }
    $sw.Stop()

    $parsed = $null
    try { $parsed = $response | ConvertFrom-Json } catch {}
    $isHit = ($null -ne $parsed -and $null -ne $parsed.result -and $null -eq $parsed.error)
    
    Write-Host "  Elapsed Time : $($sw.ElapsedMilliseconds) ms" -ForegroundColor Gray
    Write-Host "  Response Len : $(if ($response) { $response.Length } else { 0 }) bytes" -ForegroundColor Gray

    if ($expectHit) {
        if ($isHit) {
            Write-Host "  Status       : PASSED (Intercepted locally, 0 API tokens consumed)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  Status       : FAILED (Expected local intercept, but got remote/error)" -ForegroundColor Red
            return $false
        }
    } else {
        if (-not $isHit) {
            Write-Host "  Status       : PASSED (Correctly bypassed gatekeeper for new target)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  Status       : FAILED (Expected passthrough, but was intercepted)" -ForegroundColor Red
            return $false
        }
    }
}

# 1. Test Known Keyword in SERP Archive
$kw1 = [regex]::Unescape("\u304A\u9999\u304A\u3059\u3059\u3081")
$payload1 = '{"jsonrpc":"2.0","id":"t1","method":"tools/call","params":{"name":"serp_analysis","arguments":{"keyword":"' + $kw1 + '"}}}'
if (-not (Run-GatekeeperTest -testName "serp_analysis: Known keyword ($kw1)" -jsonRpcPayload $payload1 -expectHit $true)) {
    $allPassed = $false
}

# 2. Test Keyword with Zenkaku/Multiple Whitespaces
$kw2 = [regex]::Unescape("  \u304A\u9999\u3000\u304A\u3059\u3059\u3081  ")
$payload2 = '{"jsonrpc":"2.0","id":"t2","method":"tools/call","params":{"name":"serp_analysis","arguments":{"keyword":"' + $kw2 + '"}}}'
if (-not (Run-GatekeeperTest -testName "serp_analysis: Whitespace variation ($kw2)" -jsonRpcPayload $payload2 -expectHit $true)) {
    $allPassed = $false
}

# 3. Test Known Domain in Domain Keywords Archive
$payload3 = '{"jsonrpc":"2.0","id":"t3","method":"tools/call","params":{"name":"domain_keywords","arguments":{"domain":"yomu-map.jp"}}}'
if (-not (Run-GatekeeperTest -testName "domain_keywords: Known domain (yomu-map.jp)" -jsonRpcPayload $payload3 -expectHit $true)) {
    $allPassed = $false
}

# 4. Test Domain with Full URL syntax
$payload4 = '{"jsonrpc":"2.0","id":"t4","method":"tools/call","params":{"name":"domain_keywords","arguments":{"domain":"http://www.yomu-map.jp/masquerade-night/"}}}'
if (-not (Run-GatekeeperTest -testName "domain_keywords: URL format (http://www.yomu-map.jp/...)" -jsonRpcPayload $payload4 -expectHit $true)) {
    $allPassed = $false
}

# 5. Test Known Seed in Match Keywords Archive
$seed5 = [regex]::Unescape("\u65AD\u6368\u96E2")
$payload5 = '{"jsonrpc":"2.0","id":"t5","method":"tools/call","params":{"name":"match_keywords","arguments":{"keywords":["' + $seed5 + '"]}}}'
if (-not (Run-GatekeeperTest -testName "match_keywords: Known seed array ([$seed5])" -jsonRpcPayload $payload5 -expectHit $true)) {
    $allPassed = $false
}

# 6. Auto-Save & Re-intercept Roundtrip Test
Write-Host "`n[Test $global:testIndex] Roundtrip: Auto-save on remote success -> 0s intercept on 2nd call" -ForegroundColor Yellow
$global:testIndex++

$roundtripKw = "gatekeeper_auto_archive_verify_test_kw_999"
$roundtripReq = '{"jsonrpc":"2.0","id":"rt-1","method":"tools/call","params":{"name":"serp_analysis","arguments":{"keyword":"' + $roundtripKw + '"}}}'

# Clean up before test just in case
$delSql = "DELETE FROM raw_api_archive WHERE target_key = '$roundtripKw'; DELETE FROM api_call_logs WHERE target_key = '$roundtripKw'; DELETE FROM serp_cache WHERE keyword = '$roundtripKw';"
$psiClean = New-Object System.Diagnostics.ProcessStartInfo
$psiClean.FileName = $global:sqliteBin
$psiClean.Arguments = "`"$($global:researchDb)`" `"$delSql`""
$psiClean.UseShellExecute = $false
[System.Diagnostics.Process]::Start($psiClean).WaitForExit()

# Check before save (should NOT hit)
$preCheck = Invoke-GatekeeperPreflight -jsonRpcLine $roundtripReq
$preOk = ($null -eq $preCheck)
Write-Host "  Step 1: Check before save -> Allowed through = $preOk" -ForegroundColor Gray

# Mock auto-save
$mockPayload = @{
    jsonrpc = "2.0"
    id = "rt-1"
    result = @{
        content = @(
            @{
                type = "text"
                text = '{"serpEntries":[{"position":1,"domain":"sample.com","domainAuthority":3,"url":"https://sample.com/1","title":"Sample Blog"}]}'
            }
        )
    }
} | ConvertTo-Json -Depth 5 -Compress

Save-GatekeeperArchive -jsonRpcLine $roundtripReq -responsePayload $mockPayload
Write-Host "  Step 2: Auto-save executed" -ForegroundColor Gray

# Check after save (MUST hit gatekeeper in < 50ms)
$swRt = [System.Diagnostics.Stopwatch]::StartNew()
$postCheck = Forward-RemoteMcp $roundtripReq
$swRt.Stop()
$postOk = ($null -ne $postCheck -and $postCheck -match 'sample\.com')
Write-Host "  Step 3: Check after save -> Intercepted = $postOk ($($swRt.ElapsedMilliseconds) ms)" -ForegroundColor Gray

# Cleanup
[System.Diagnostics.Process]::Start($psiClean).WaitForExit()
Write-Host "  Step 4: Cleaned up test record" -ForegroundColor Gray

if ($preOk -and $postOk) {
    Write-Host "  Status       : PASSED (Full auto-archive & intercept lifecycle confirmed)" -ForegroundColor Green
} else {
    Write-Host "  Status       : FAILED (Roundtrip lifecycle check failed)" -ForegroundColor Red
    $allPassed = $false
}

Write-Host "`n============================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "   ALL GATEKEEPER UNIT TESTS PASSED SUCCESSFULLY!          " -ForegroundColor Green
} else {
    Write-Host "   SOME GATEKEEPER TESTS FAILED. CHECK LOGS ABOVE.         " -ForegroundColor Red
}
Write-Host "============================================================" -ForegroundColor Cyan

if (-not $allPassed) { exit 1 }
