param(
  [Parameter(Mandatory = $true)]
  [string]$Email,

  [Parameter(Mandatory = $true)]
  [string]$Password,

  [string]$ApiBaseUrl = "http://localhost:3020/api/v1",

  [string]$EnvFilePath = "..\..\e2e_sdk_tests\react\test_1\.env.local"
)

$ErrorActionPreference = "Stop"
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }

function Resolve-ProjectPath([string]$PathValue) {
  return [System.IO.Path]::GetFullPath((Join-Path $script:ScriptRoot $PathValue))
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

try {
  $resolvedEnvPath = Resolve-ProjectPath $EnvFilePath
  $loginUrl = "$($ApiBaseUrl.TrimEnd('/'))/auth/login"

  Write-Host "Login API: $loginUrl"
  Write-Host "Mise a jour de: $resolvedEnvPath"

  $body = @{
    email = $Email
    password = $Password
  } | ConvertTo-Json

  $response = Invoke-RestMethod `
    -Uri $loginUrl `
    -Method Post `
    -ContentType "application/json" `
    -Body $body

  $token = Extract-Token $response
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Token introuvable dans la reponse /auth/login."
  }

  Upsert-EnvValue -FilePath $resolvedEnvPath -Key "NEXT_PUBLIC_TRUSTDEV_SDK_TOKEN" -Value $token

  Write-Host "Token SDK rafraichi avec succes."
  Write-Host "Pense a redemarrer l'app Next.js si elle etait deja lancee."
}
catch {
  Write-Error "Echec refresh token: $($_.Exception.Message)"
  exit 1
}
