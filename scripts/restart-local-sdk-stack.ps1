param(
  [switch]$RefreshToken,
  [string]$Email,
  [string]$Password,
  [string]$TestProject = "test_1",
  [ValidateSet("prod", "dev")]
  [string]$AppMode = "prod",
  [switch]$FallbackToDevOnProdBuildFailure = $true,
  [int]$AppPort = 3000,
  [switch]$KillBackendPort3020,
  [switch]$SkipSdkInit,
  [switch]$ForceSdkInit,
  [switch]$StartTunnel = $true,
  [string]$TunnelCommand = "npx --yes tunnelmole 3000"
)

$ErrorActionPreference = "Stop"
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }

function Resolve-FromScripts([string]$RelativePath) {
  return [System.IO.Path]::GetFullPath((Join-Path $script:ScriptRoot $RelativePath))
}

function Invoke-Step([string]$Name, [scriptblock]$Action) {
  Write-Host ""
  Write-Host "==> $Name"
  & $Action
}

function Stop-PortListeners([int[]]$Ports) {
  foreach ($port in $Ports) {
    $listeners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($listener in $listeners) {
      $processId = $listener.OwningProcess
      if ($processId -and $processId -gt 0) {
        try {
          Stop-Process -Id $processId -Force -ErrorAction Stop
          Write-Host "Processus tue sur port $port (PID=$processId)."
        } catch {
          Write-Warning "Impossible de tuer PID=$processId sur port ${port}: $($_.Exception.Message)"
        }
      }
    }
  }
}

function Stop-TunnelProcesses {
  $targets = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -in @("node.exe", "npx.cmd") -and
      $_.CommandLine -match "tunnelmole"
    }

  foreach ($proc in $targets) {
    try {
      Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
      Write-Host "Tunnel process tue (PID=$($proc.ProcessId))."
    } catch {
      Write-Warning "Impossible de tuer PID=$($proc.ProcessId): $($_.Exception.Message)"
    }
  }
}

function Test-PortListening([int]$Port) {
  $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  return $null -ne $listener
}

function Clear-TestAppCache([string]$TestAppDir) {
  $cachePaths = @(
    (Join-Path $TestAppDir ".next"),
    (Join-Path $TestAppDir "node_modules\.cache")
  )

  foreach ($cachePath in $cachePaths) {
    if (Test-Path -Path $cachePath) {
      Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
      Write-Host "Cache supprime: $cachePath"
    }
  }
}

function Enable-SystemCAForNode {
  $nodeFlag = "--use-system-ca"
  $current = [string]$env:NODE_OPTIONS
  if ($current -notmatch "(^|\s)--use-system-ca(\s|$)") {
    $env:NODE_OPTIONS = if ([string]::IsNullOrWhiteSpace($current)) { $nodeFlag } else { "$current $nodeFlag" }
  }
  Write-Host "NODE_OPTIONS actif: $env:NODE_OPTIONS"
}

function Test-TrustDevSdkInitialized([string]$TestAppDir) {
  $componentPath = Join-Path $TestAppDir "components\trustdev\trustdev-onboarding.tsx"
  $envPath = Join-Path $TestAppDir ".env.local"
  $layoutCandidates = @(
    (Join-Path $TestAppDir "app\layout.tsx"),
    (Join-Path $TestAppDir "src\app\layout.tsx")
  )
  $layoutPath = $layoutCandidates | Where-Object { Test-Path -Path $_ -PathType Leaf } | Select-Object -First 1

  if (-not (Test-Path -Path $componentPath -PathType Leaf)) { return $false }
  if (-not (Test-Path -Path $envPath -PathType Leaf)) { return $false }
  if (-not $layoutPath) { return $false }

  $componentContent = Get-Content -Path $componentPath -Raw
  $envContent = Get-Content -Path $envPath -Raw
  $layoutContent = Get-Content -Path $layoutPath -Raw

  $componentReady =
    $componentContent -match "export\s+function\s+TrustdevOnboarding" -and
    $componentContent -match "TourViewer"

  $layoutReady =
    $layoutContent -match "TrustdevOnboarding" -and
    $layoutContent -match "<TrustdevOnboarding\s*/>"

  $requiredEnvKeys = @(
    "NEXT_PUBLIC_TRUSTDEV_API_URL",
    "NEXT_PUBLIC_TRUSTDEV_API_KEY",
    "NEXT_PUBLIC_TRUSTDEV_ORGANIZATION_ID",
    "NEXT_PUBLIC_TRUSTDEV_SDK_TOKEN"
  )
  $envReady = $true
  foreach ($key in $requiredEnvKeys) {
    if ($envContent -notmatch "(?m)^\s*$key\s*=") {
      $envReady = $false
      break
    }
  }

  return ($componentReady -and $layoutReady -and $envReady)
}

try {
  $repoRoot = Resolve-FromScripts ".."
  $sdkReactDir = Resolve-FromScripts "..\sdks\react"
  $testAppDir = Resolve-FromScripts "..\..\e2e_sdk_tests\react\$TestProject"
  $tokenScriptPath = Resolve-FromScripts ".\refresh-sdk-token.ps1"
  $sdkTgzPath = Join-Path $sdkReactDir "trustdev-onboarding-sdk-react-0.1.0.tgz"
  $effectiveAppMode = $AppMode

  if (-not (Test-Path -Path $testAppDir -PathType Container)) {
    throw "Projet de test introuvable: '$TestProject' (chemin resolu: $testAppDir)."
  }

  Invoke-Step "Activation Node CA systeme" {
    Enable-SystemCAForNode
  }

  Invoke-Step "Nettoyage des process existants (ports 3000, 3001)" {
    $portsToKill = @(3000, 3001)
    if ($KillBackendPort3020) {
      $portsToKill += 3020
    }
    Stop-PortListeners -Ports $portsToKill
    Stop-TunnelProcesses
  }

  Invoke-Step "Purge cache Next.js ($TestProject)" {
    Clear-TestAppCache -TestAppDir $testAppDir
  }

  if ($RefreshToken) {
    if ([string]::IsNullOrWhiteSpace($Email) -or [string]::IsNullOrWhiteSpace($Password)) {
      throw "Utilise -Email et -Password quand -RefreshToken est active."
    }
    if (-not (Test-PortListening -Port 3020)) {
      throw "Le backend API (port 3020) n'est pas demarre. Demarre-le puis relance le script avec -RefreshToken."
    }
  }

  Invoke-Step "Build + pack SDK React local" {
    Push-Location $sdkReactDir
    try {
      npm run build
      if ($LASTEXITCODE -ne 0) { throw "npm run build a echoue." }
      npm pack
      if ($LASTEXITCODE -ne 0) { throw "npm pack a echoue." }
    } finally {
      Pop-Location
    }
  }

  Invoke-Step "Reinstall SDK dans $TestProject" {
    Push-Location $testAppDir
    try {
      npm install $sdkTgzPath
      if ($LASTEXITCODE -ne 0) { throw "npm install tgz a echoue." }
    } finally {
      Pop-Location
    }
  }

  $sdkAlreadyInitialized = Test-TrustDevSdkInitialized -TestAppDir $testAppDir

  if ($SkipSdkInit) {
    Write-Host ""
    Write-Host "==> Initialisation TrustDev SDK ignoree (-SkipSdkInit)"
  } elseif ($sdkAlreadyInitialized -and -not $ForceSdkInit) {
    Write-Host ""
    Write-Host "==> Initialisation TrustDev SDK deja faite pour $TestProject (skip automatique)"
    Write-Host "Astuce: utilise -ForceSdkInit pour relancer l'init volontairement."
  } else {
    Invoke-Step "Initialisation TrustDev SDK dans $TestProject" {
      $localInitScript = Join-Path $testAppDir "node_modules\@trustdev\onboarding-sdk-react\scripts\init.js"
      $sourceInitScript = Join-Path $sdkReactDir "scripts\init.js"
      $initScript = if (Test-Path -Path $localInitScript -PathType Leaf) { $localInitScript } else { $sourceInitScript }

      if (-not (Test-Path -Path $initScript -PathType Leaf)) {
        throw "Script init TrustDev introuvable. Attendu: $localInitScript"
      }

      Push-Location $testAppDir
      try {
        Write-Host "Lancement init local: node `"$initScript`""
        node $initScript
        if ($LASTEXITCODE -ne 0) { throw "trustdev init a echoue." }
      } finally {
        Pop-Location
      }
    }
  }

  if ($RefreshToken) {
    Invoke-Step "Refresh token SDK" {
      & $tokenScriptPath -Email $Email -Password $Password -TestProject $TestProject
      if (-not $?) { throw "Echec refresh-sdk-token.ps1" }
    }
  }

  if ($AppMode -eq "prod") {
    Invoke-Step "Build $TestProject (mode prod)" {
      Push-Location $testAppDir
      try {
        $buildSucceeded = $false
        $env:NEXT_DISABLE_SWC_WORKER = "1"
        $env:NEXT_TELEMETRY_DISABLED = "1"
        for ($attempt = 1; $attempt -le 2; $attempt++) {
          npm run build
          if ($LASTEXITCODE -eq 0) {
            $buildSucceeded = $true
            break
          }
          Write-Warning "Build Next.js echoue (tentative $attempt/2)."
          if ($attempt -lt 2) {
            Start-Sleep -Seconds 2
          }
        }

        if (-not $buildSucceeded) {
          if ($FallbackToDevOnProdBuildFailure) {
            Write-Warning "Build prod instable sur cet environnement. Bascule automatique en mode dev."
            $script:effectiveAppMode = "dev"
          } else {
            throw "npm run build ($TestProject) a echoue."
          }
        }
      } finally {
        Remove-Item Env:NEXT_DISABLE_SWC_WORKER -ErrorAction SilentlyContinue
        Remove-Item Env:NEXT_TELEMETRY_DISABLED -ErrorAction SilentlyContinue
        Pop-Location
      }
    }
  }

  Invoke-Step "Lancement Next $effectiveAppMode (nouveau terminal)" {
    $runCommand = if ($effectiveAppMode -eq "prod") { "npm run start" } else { "npm run dev" }
    $appCmd = "cd /d `"$testAppDir`" && set NODE_OPTIONS=$env:NODE_OPTIONS && $runCommand"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/k", $appCmd | Out-Null
    Write-Host "Next.js ($effectiveAppMode) en cours de demarrage sur http://localhost:$AppPort"
  }

  if ($StartTunnel) {
    Invoke-Step "Lancement tunnel (nouveau terminal)" {
      $tunnelCmd = "cd /d `"$testAppDir`" && $TunnelCommand"
      Start-Process -FilePath "cmd.exe" -ArgumentList "/k", $tunnelCmd | Out-Null
      Write-Host "Tunnel lance avec commande: $TunnelCommand"
    }
  }

  Write-Host ""
  Write-Host "Workflow termine."
  Write-Host "Astuce: attends 5-10s, puis ouvre localhost et l'URL tunnel."
}
catch {
  Write-Error "Echec restart-local-sdk-stack.ps1: $($_.Exception.Message)"
  exit 1
}
