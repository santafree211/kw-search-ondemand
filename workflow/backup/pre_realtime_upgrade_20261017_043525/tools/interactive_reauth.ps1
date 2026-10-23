<#
.SYNOPSIS
    tools/interactive_reauth.ps1
    Responsibility: One-click interactive OAuth 2.0 PKCE authentication flow for Ubersuggest MCP.
    Spins up local HTTP listener on port 8080, launches browser for authorization, exchanges code for fresh tokens,
    and atomically updates mcp_oauth_tokens.json.
#>

$ErrorActionPreference = "Stop"

Write-Output "=========================================================="
Write-Output "=== UBERSUGGEST MCP INTERACTIVE RE-AUTHENTICATION ==="
Write-Output "=========================================================="

# 1. Generate PKCE
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$state = [Convert]::ToBase64String($bytes) -replace '\+','-' -replace '/','_' -replace '='

$vbytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($vbytes)
$verifier = [Convert]::ToBase64String($vbytes) -replace '\+','-' -replace '/','_' -replace '='

$sha256 = [System.Security.Cryptography.SHA256]::Create()
$cbytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($verifier))
$challenge = [Convert]::ToBase64String($cbytes) -replace '\+','-' -replace '/','_' -replace '='

# 2. Build Authorize URL
$params = @{
    response_type         = "code"
    client_id             = "ubersuggest-mcp"
    redirect_uri          = "http://localhost:8080/callback"
    state                 = $state
    code_challenge        = $challenge
    code_challenge_method = "S256"
    scope                 = "profile domain keywords serp backlinks site_audit content projects utility"
}

$queryString = ($params.Keys | ForEach-Object { "$_=$([uri]::EscapeDataString($params[$_]))" }) -join "&"
$authUrl = "https://ubersuggest-mcp.neilpatelapi.com/authorize?$queryString"

Write-Output "Opening browser for Ubersuggest Authorization..."
Write-Output "Authorize URL: $authUrl"

# 3. Start Local HTTP Listener on 8080
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8080/")

try {
    $listener.Start()
} catch {
    Write-Error "Failed to start listener on http://localhost:8080/: $_"
    exit 1
}

# 4. Open default browser
Start-Process $authUrl

Write-Output "`n>>> Waiting for authorization callback in browser (timeout 600s)... <<<"

# 5. Wait for request with timeout
$asyncResult = $listener.BeginGetContext($null, $null)
$waitSuccess = $asyncResult.AsyncWaitHandle.WaitOne(600000) # 10 minutes

if (-not $waitSuccess) {
    $listener.Stop()
    Write-Error "Authorization timed out. Please try again."
    exit 1
}

$context = $listener.EndGetContext($asyncResult)
$req = $context.Request
$rawUrl = $req.RawUrl
Write-Output "Received callback request: $rawUrl"

# Send success response to browser
$res = $context.Response
$responseHtml = "<html><body style='font-family:sans-serif;text-align:center;padding:50px;background:#f0fdf4;'><h2 style='color:#16a34a;'>Authentication Successful!</h2><p>Ubersuggest MCP has been successfully authorized. You can close this tab now.</p></body></html>"
$buffer = [System.Text.Encoding]::UTF8.GetBytes($responseHtml)
$res.ContentLength64 = $buffer.Length
$res.OutputStream.Write($buffer, 0, $buffer.Length)
$res.OutputStream.Close()
$listener.Stop()

# 6. Parse authorization code
$authCode = $null
if ($rawUrl -match '[?&]code=([^&]+)') {
    $authCode = [System.Uri]::UnescapeDataString($matches[1])
}

if ([string]::IsNullOrWhiteSpace($authCode)) {
    Write-Error "No authorization code found in callback query: $rawUrl"
    exit 1
}

Write-Output "Authorization Code received successfully! Exchanging for tokens..."

# 7. Exchange Code for Tokens
$tokenBody = @{
    grant_type    = "authorization_code"
    client_id     = "ubersuggest-mcp"
    code          = $authCode
    redirect_uri  = "http://localhost:8080/callback"
    code_verifier = $verifier
}

try {
    $tokenRes = Invoke-RestMethod -Uri "https://ubersuggest-mcp.neilpatelapi.com/token" -Method Post -Body $tokenBody -TimeoutSec 15
} catch {
    Write-Error "Token exchange failed: $_"
    exit 1
}

if (-not $tokenRes.access_token) {
    Write-Error "Token response missing access_token: $($tokenRes | ConvertTo-Json)"
    exit 1
}

$newAccessToken = $tokenRes.access_token
$newRefreshToken = $tokenRes.refresh_token
$newExpiresIn = if ($tokenRes.expires_in) { [int]$tokenRes.expires_in } else { 172800 }
$newExpiry = (Get-Date).AddSeconds($newExpiresIn).ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")

Write-Output "Token exchange SUCCESS! New token valid until $newExpiry."

# 8. Save updated tokens to mcp_oauth_tokens.json
$oauthPath = "C:\Users\santa\.gemini\antigravity\mcp_oauth_tokens.json"
$oauthConfig = @{
    "https://ubersuggest-mcp.neilpatelapi.com/mcp" = @{
        client_id = "ubersuggest-mcp"
        token = @{
            access_token  = $newAccessToken
            token_type    = "Bearer"
            refresh_token = $newRefreshToken
            expiry        = $newExpiry
        }
        token_url = "https://ubersuggest-mcp.neilpatelapi.com/token"
    }
}
$oauthJson = $oauthConfig | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($oauthPath, $oauthJson, (New-Object System.Text.UTF8Encoding $false))
Write-Output "Saved fresh tokens to $oauthPath"

# 9. Verify API Health immediately
Write-Output "`nVerifying API Health with new tokens..."
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\check_api_health.ps1"
