param(
  [Parameter(Mandatory = $true)]
  [string]$Email,

  [Parameter(Mandatory = $true)]
  [string]$Password,

  [string]$ApiBaseUrl = "http://localhost:3020/api/v1",

  [int]$MaxRetries = 4,

  [int]$RetryDelayMs = 1200,

  [string]$TestProject = "test_1",

  [string]$EnvFilePath = "",

  # Legacy: write session JWT into NEXT_PUBLIC_TRUSTDEV_SDK_TOKEN (deprecated).
  [switch]$UseSessionJwt,

  # Omit tours:publish on the integration PAT (use -SkipPublishScope).
  [switch]$SkipPublishScope,

  # Also sync PAT into dashboard/.env.local for SDK Tests lab.
  [switch]$SkipDashboardEnvSync
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

function Extract-OrganizationId($LoginResponse, [string]$SessionJwt) {
  $fromUser = $LoginResponse.user.organizationId
  if (-not [string]::IsNullOrWhiteSpace($fromUser)) {
    return [string]$fromUser
  }
  return Extract-JwtOrganizationId $SessionJwt
}

function Upsert-EnvValue(
  [string]$FilePath,
  [string]$Key,
  [string]$Value
) {
  $parentDir = Split-Path -Parent $FilePath
  if (-not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  if (Test-Path $FilePath) {
    $existingLines = Get-Content -Path $FilePath -Encoding UTF8
    foreach ($line in $existingLines) {
      $lines.Add([string]$line)
    }
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

function Ensure-EnvDefaults([string]$FilePath) {
  $defaults = @{
    "NEXT_PUBLIC_TRUSTDEV_API_URL" = "http://localhost:3020/api/v1"
    "NEXT_PUBLIC_TRUSTDEV_API_KEY" = "demo-local-key"
    "NEXT_PUBLIC_TRUSTDEV_SEMANTIC_ENGINE_MODE" = "hybrid"
  }
  foreach ($entry in $defaults.GetEnumerator()) {
    if (-not (Test-Path $FilePath)) {
      Upsert-EnvValue -FilePath $FilePath -Key $entry.Key -Value $entry.Value
      continue
    }
    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
    if ($content -notmatch "(?m)^\s*$([regex]::Escape($entry.Key))\s*=") {
      Upsert-EnvValue -FilePath $FilePath -Key $entry.Key -Value $entry.Value
    }
  }
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

function Sync-SdkPatEnvFile(
  [string]$FilePath,
  [string]$Token,
  [string]$OrganizationId
) {
  Ensure-EnvDefaults -FilePath $FilePath
  Upsert-EnvValue -FilePath $FilePath -Key "NEXT_PUBLIC_TRUSTDEV_SDK_TOKEN" -Value $Token
  if (-not [string]::IsNullOrWhiteSpace($OrganizationId)) {
    Upsert-EnvValue -FilePath $FilePath -Key "NEXT_PUBLIC_TRUSTDEV_ORGANIZATION_ID" -Value $OrganizationId
  }
}

try {
  $resolvedEnvPath = if ([string]::IsNullOrWhiteSpace($EnvFilePath)) {
    Resolve-ProjectPath "..\..\e2e_sdk_tests\react\$TestProject\.env.local"
  } else {
    Resolve-ProjectPath $EnvFilePath
  }
  $dashboardEnvPath = Resolve-ProjectPath "..\dashboard\.env.local"
  $loginUrl = "$($ApiBaseUrl.TrimEnd('/'))/auth/login"

  Write-Host "Login API: $loginUrl"
  Write-Host "Mise a jour PAT e2e: $resolvedEnvPath"

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

  $organizationId = Extract-OrganizationId $response $sessionJwt
  $tokenToStore = $sessionJwt

  if ($UseSessionJwt) {
    Write-Warning "Mode JWT session (deprecated). Preferez le PAT td_sdk_ par defaut."
  } else {
    $scopes = @(
      "tours:runtime",
      "tours:sandbox",
      "blueprints:read",
      "feedback:read",
      "feedback:write",
      "semantic:invoke",
      "faq:search"
    )
    if (-not $SkipPublishScope) {
      $scopes += "tours:publish"
    }

    $createBody = @{
      name = "e2e-$TestProject-$(Get-Date -Format 'yyyyMMdd-HHmm')"
      scopes = $scopes
    } | ConvertTo-Json

    $createUrl = "$($ApiBaseUrl.TrimEnd('/'))/auth/sdk-tokens"
    Write-Host "Creation token integration (PAT): $createUrl"

    $createResp = Invoke-RestMethod `
      -Uri $createUrl `
      -Method Post `
      -ContentType "application/json" `
      -Headers @{ Authorization = "Bearer $sessionJwt" } `
      -Body $createBody

    if ([string]::IsNullOrWhiteSpace($createResp.token)) {
      throw "Reponse /auth/sdk-tokens sans champ token."
    }

    if (-not $createResp.token.StartsWith("td_sdk_")) {
      throw "Token integration inattendu (prefix td_sdk_ requis)."
    }

    $tokenToStore = $createResp.token
    Write-Host "PAT cree. Scopes: $($scopes -join ', ')"
  }

  Sync-SdkPatEnvFile -FilePath $resolvedEnvPath -Token $tokenToStore -OrganizationId $organizationId
  Write-Host "NEXT_PUBLIC_TRUSTDEV_SDK_TOKEN mis a jour (e2e)."

  if (-not $SkipDashboardEnvSync -and -not $UseSessionJwt) {
    Sync-SdkPatEnvFile -FilePath $dashboardEnvPath -Token $tokenToStore -OrganizationId $organizationId
    Upsert-EnvValue -FilePath $dashboardEnvPath -Key "NEXT_PUBLIC_API_URL" -Value $ApiBaseUrl
    Upsert-EnvValue -FilePath $dashboardEnvPath -Key "NEXT_PUBLIC_SDK_API_KEY" -Value "trustdev-sdk-tests"
    Write-Host "Dashboard lab synchronise: $dashboardEnvPath"
  }

  if (-not [string]::IsNullOrWhiteSpace($organizationId)) {
    Write-Host "Organization ID: $organizationId"
  }

  Write-Host "Redemarrez l'app Next.js et le dashboard si ils etaient deja lances."
}
catch {
  Write-Error "Echec refresh token: $($_.Exception.Message)"
  exit 1
}
