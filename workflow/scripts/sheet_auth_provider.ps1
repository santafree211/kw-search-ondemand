<#
.SYNOPSIS
    sheet_auth_provider.ps1
    Responsibility: Authenticate with Google API using service account credentials and return an access token.
#>

function Get-GoogleAccessToken {
    param([string]$JsonPath = "")

    if ([string]::IsNullOrWhiteSpace($JsonPath)) {
        $candidate = Join-Path $PSScriptRoot "..\..\impactful-name-461818-t0-de11450b528d.json"
        if (Test-Path $candidate) {
            $JsonPath = (Resolve-Path $candidate).Path
        } else {
            $JsonPath = "c:\Users\user\OneDrive\prideall\projects\kw-serch\impactful-name-461818-t0-de11450b528d.json"
        }
    }

    if (-not (Test-Path $JsonPath)) {
        throw "Service account JSON not found at: $JsonPath"
    }

    $json = Get-Content $JsonPath -Raw | ConvertFrom-Json
    $clientEmail = $json.client_email
    $privateKeyPem = $json.private_key

    function Parse-Pkcs8PrivateKey([string]$pem) {
        $clean = $pem -replace '-----BEGIN PRIVATE KEY-----', '' -replace '-----END PRIVATE KEY-----', '' -replace '\s+', ''
        $bytes = [Convert]::FromBase64String($clean)
        $reader = New-Object System.IO.BinaryReader(New-Object System.IO.MemoryStream(,$bytes))
        function Read-Length($r) {
            $b = $r.ReadByte()
            if (($b -band 0x80) -eq 0) { return $b }
            $count = $b -band 0x7F
            $len = 0
            for ($i = 0; $i -lt $count; $i++) { $len = ($len -shl 8) -bor $r.ReadByte() }
            return $len
        }
        $r = $reader
        $r.ReadByte() | Out-Null; Read-Length $r | Out-Null; $r.ReadByte() | Out-Null; $r.ReadByte() | Out-Null; $r.ReadByte() | Out-Null; $r.ReadByte() | Out-Null
        $algoLen = Read-Length $r; $r.ReadBytes($algoLen) | Out-Null; $r.ReadByte() | Out-Null; $octetLen = Read-Length $r; $r.ReadByte() | Out-Null; Read-Length $r | Out-Null
        function Read-IntegerBytes($r) {
            $r.ReadByte() | Out-Null; $len = Read-Length $r; $data = $r.ReadBytes($len)
            if ($data[0] -eq 0) { $data = $data[1..($data.Length-1)] }
            return $data
        }
        Read-IntegerBytes $r | Out-Null; $n = Read-IntegerBytes $r; $e = Read-IntegerBytes $r; $d = Read-IntegerBytes $r; $p = Read-IntegerBytes $r; $q = Read-IntegerBytes $r; $dp = Read-IntegerBytes $r; $dq = Read-IntegerBytes $r; $iq = Read-IntegerBytes $r
        $rsaParams = New-Object System.Security.Cryptography.RSAParameters
        $rsaParams.Modulus = $n; $rsaParams.Exponent = $e; $rsaParams.D = $d; $rsaParams.P = $p; $rsaParams.Q = $q; $rsaParams.DP = $dp; $rsaParams.DQ = $dq; $rsaParams.InverseQ = $iq
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsa.ImportParameters($rsaParams)
        return $rsa
    }

    $rsa = Parse-Pkcs8PrivateKey $privateKeyPem
    function Base64UrlEncode([byte[]]$b) { [Convert]::ToBase64String($b).Replace('+', '-').Replace('/', '_').TrimEnd('=') }

    $header = '{"alg":"RS256","typ":"JWT"}'
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $exp = $now + 3600
    $claimSet = @{
        iss = $clientEmail
        scope = "https://www.googleapis.com/auth/spreadsheets"
        aud = "https://oauth2.googleapis.com/token"
        exp = $exp
        iat = $now
    } | ConvertTo-Json -Compress

    $hEnc = Base64UrlEncode ([System.Text.Encoding]::UTF8.GetBytes($header))
    $cEnc = Base64UrlEncode ([System.Text.Encoding]::UTF8.GetBytes($claimSet))
    $inputStr = "$hEnc.$cEnc"
    $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($inputStr)
    $sha256 = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
    $sigBytes = $rsa.SignData($inputBytes, $sha256)
    $sigEnc = Base64UrlEncode $sigBytes
    $jwt = "$inputStr.$sigEnc"

    $body = @{ grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"; assertion = $jwt }
    $tokenResponse = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body $body
    return $tokenResponse.access_token
}


