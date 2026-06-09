param(
  [Parameter(Mandatory = $true)]
  [string]$Email,

  [Parameter(Mandatory = $true)]
  [string]$Password,

  [string]$ApiBaseUrl = "http://localhost:3020/api/v1",

  [int]$MaxRetries = 4,

  [int]$RetryDelayMs = 1200,

  [string]$TestProject = "test_1",

  [string]$EnvFilePath = "..\..\e2e_sdk_tests\react\test_1\.env.local",

  # Create a scoped integration token (td_sdk_...) instead of copying the session JWT.
  [switch]$UseIntegrationToken,

  # Add tours:publish scope (ADMIN login only — ignored server-side for DEVELOPER).
  [switch]$IncludePublishScope
)

$ErrorActionPreference = "Stop"
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }

function Resolve-ProjectPath([string]$PathValue) {
  return [System.IO.Path]::GetFullPath((Join-Path $script:ScriptRoot $PathValue))
}

function Extract-JwtOrganizationId([string]$Token) {
  if ([string]::IsNullOrWhiteSpace($Token)) { return $null }
  if ($Token.StartsWith("td_sdk_")) { return $null }
  $parts = $Token.Split('.')
  if ($parts.Count -lt 2) { return $null }

  $payload = $parts[1]
  $mod = $payload.Length % 4
  if ($mod -gt 0) { $payload = $payload + ('=' * (4 - $mod)) }

  try {
    $bytes = [System.Convert]::FromBase64String($payload.Replace('-', '+').Replace('_', '/'))
    $json = [System.Text.Encoding]::UTF8.GetString($bytes)
    $parsed = $json | ConvertFrom-Json
    return $parsed.organizationId
  } catch {
    return $null
  }
}

function Extract-Token($LoginResponse) {
  if ($null -eq $LoginResponse) { return $null }

  $candidates = @((
    $LoginResponse.access_token,
    $LoginResponse.accessToken,
    $LoginResponse.token,
    $LoginResponse.jwt,
    $LoginResponse.data.access_token,
    $LoginResponse.data.accessToken,
    $LoginResponse.data.token,
    $LoginResponse.user.accessToken
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

  if ($candidates.Count -gt 0) {
    return $candidates[0]
  }

  return $null
}

function Upsert-EnvValue(
  [string]$FilePath,
  [string]$Key,
  [string]$Value
) {
  if (-not (Test-Path $FilePath)) {
    throw "Fichier introuvable: $FilePath"
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  $existingLines = Get-Content -Path $FilePath -Encoding UTF8
  foreach ($line in $existingLines) {
    $lines.Add([string]$line)
  }

  $prefix = "$Key="
  $found = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith($prefix)) {
      $lines[$i] = "$Key=$Value"
      $found = $true
      break
    }
  }

  if (-not $found) {
    $lines.Add("$Key=$Value")
  }

  Set-Content -Path $FilePath -Value $lines -Encoding UTF8
}

function Invoke-LoginWithRetry(
  [string]$Url,
  [string]$JsonBody,
  [int]$Attempts,
  [int]$DelayMs
) {
  $lastError = $null
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    try {
      return Invoke-RestMethod `
        -Uri $Url `
        -Method Post `
        -ContentType "application/json" `
        -Body $JsonBody
    }
    catch {
      $lastError = $_
      if ($attempt -lt $Attempts) {
        Write-Warning "Login attempt $attempt/$Attempts a echoue: $($_.Exception.Message)"
        Start-Sleep -Milliseconds ($DelayMs * $attempt)
      }
    }
  }

  if ($null -ne $lastError) {
    throw $lastError.Exception
  }
  throw "Echec login API sans details."
}

try {
  $resolvedEnvPath = if ($PSBoundParameters.ContainsKey("EnvFilePath")) {
    Resolve-ProjectPath $EnvFilePath
  } else {
    Resolve-ProjectPath "..\..\e2e_sdk_tests\react\$TestProject\.env.local"
  }
  $loginUrl = "$($ApiBaseUrl.TrimEnd('/'))/auth/login"

  Write-Host "Login API: $loginUrl"
  Write-Host "Mise a jour de: $resolvedEnvPath"

  $body = @{
    email = $Email
    password = $Password
  } | ConvertTo-Json

  $response = Invoke-LoginWithRetry `
    -Url $loginUrl `
    -JsonBody $body `
    -Attempts ([Math]::Max(1, $MaxRetries)) `
    -DelayMs ([Math]::Max(200, $RetryDelayMs))

  $sessionJwt = Extract-Token $response
  if ([string]::IsNullOrWhiteSpace($sessionJwt)) {
    throw "Token introuvable dans la reponse /auth/login."
  }

  $tokenToStore = $sessionJwt

  if ($UseIntegrationToken) {
    $scopes = @(
      "tours:runtime",
      "tours:sandbox",
      "blueprints:read",
      "feedback:read",
      "feedback:write",
      "semantic:invoke"
    )
    if ($IncludePublishScope) {
      $scopes += "tours:publish"
    }

    $createBody = @{
      name = "e2e-$TestProject-$(Get-Date -Format 'yyyyMMdd-HHmm')"
      scopes = $scopes
    } | ConvertTo-Json

    $createUrl = "$($ApiBaseUrl.TrimEnd('/'))/auth/sdk-tokens"
    Write-Host "Creation token integration: $createUrl"

    $createResp = Invoke-RestMethod `
      -Uri $createUrl `
      -Method Post `
      -ContentType "application/json" `
      -Headers @{ Authorization = "Bearer $sessionJwt" } `
      -Body $createBody

    if ([string]::IsNullOrWhiteSpace($createResp.token)) {
      throw "Reponse /auth/sdk-tokens sans champ token."
    }

    $tokenToStore = $createResp.token
    Write-Host "Token integration cree (prefix td_sdk_). Scopes: $($scopes -join ', ')"
  } else {
    Write-Warning "Mode JWT session: privilegie -UseIntegrationToken pour un token scope limite."
  }

  Upsert-EnvValue -FilePath $resolvedEnvPath -Key "NEXT_PUBLIC_TRUSTDEV_SDK_TOKEN" -Value $tokenToStore

  $organizationId = Extract-JwtOrganizationId $sessionJwt
  if (-not [string]::IsNullOrWhiteSpace($organizationId)) {
    Upsert-EnvValue -FilePath $resolvedEnvPath -Key "NEXT_PUBLIC_TRUSTDEV_ORGANIZATION_ID" -Value $organizationId
    Write-Host "Organization ID synchronise depuis le JWT de session."
  }

  Write-Host "NEXT_PUBLIC_TRUSTDEV_SDK_TOKEN mis a jour."
  Write-Host "Redemarrez l'app Next.js si elle etait deja lancee."
}
catch {
  Write-Error "Echec refresh token: $($_.Exception.Message)"
  exit 1
}
