<#
.SYNOPSIS
  Build SDK, (re)init test app, refresh token, start Next.js + optional tunnel.

.EXAMPLE
  # Heuristique + singlePageTour (test_9 / test_10)
  .\restart-local-sdk-stack.ps1 -TestProject test_10 -SdkInitMode heuristic -SinglePageTour `
    -RefreshToken -Email "you@example.com" -Password "secret"

.EXAMPLE
  # Blueprints (test_6)
  .\restart-local-sdk-stack.ps1 -TestProject test_6 -SdkInitMode blueprints -BlueprintPack fintech `
    -RefreshToken -Email "you@example.com" -Password "secret"

.EXAMPLE
  # Relance sans re-init (projet deja configure)
  .\restart-local-sdk-stack.ps1 -TestProject test_10 -SdkInitMode heuristic -SinglePageTour -SkipSdkInit `
    -RefreshToken -Email "you@example.com" -Password "secret"
#>
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
  [switch]$SkipSdkReinstall,
  [switch]$ForceSdkInit,
  [ValidateSet("", "heuristic", "blueprints")]
  [string]$SdkInitMode = "",
  [ValidateSet("fintech", "healthtech", "tech", "hr", "social", "elearning", "realestate", "productivity", "multi-vertical")]
  [string]$BlueprintPack = "fintech",
  [switch]$SinglePageTour,
  [string]$ProjectDomain = "",
  [switch]$StartTunnel = $true,
  [string]$TunnelCommand = "npx --yes tunnelmole 3000"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
  throw "PSScriptRoot indisponible. Lance ce script avec: powershell -File `"chemin\restart-local-sdk-stack.ps1`" -TestProject test_11 ..."
}
$script:ScriptRoot = $PSScriptRoot

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

function Build-TrustDevInitArgs(
  [string]$Mode,
  [string]$Pack,
  [switch]$SinglePageTour,
  [string]$ProjectDomain,
  [string]$TargetDir,
  [switch]$NonInteractive
) {
  $initArgs = @()
  if ($NonInteractive) { $initArgs += "--yes" }
  if (-not [string]::IsNullOrWhiteSpace($TargetDir)) {
    $initArgs += "--target-dir=$TargetDir"
  }
  if (-not [string]::IsNullOrWhiteSpace($Mode)) {
    $initArgs += "--mode=$Mode"
    if ($Mode -eq "blueprints" -and -not [string]::IsNullOrWhiteSpace($Pack)) {
      $initArgs += "--pack=$Pack"
    }
    if ($Mode -eq "heuristic") {
      if ($SinglePageTour) { $initArgs += "--single-page-tour" }
      if (-not [string]::IsNullOrWhiteSpace($ProjectDomain)) {
        $initArgs += "--project-domain=$ProjectDomain"
      }
    }
  }
  return $initArgs
}

function Format-CmdExeChain([string]$WorkDir, [string]$Command) {
  return ('cd /d "{0}" && {1}' -f $WorkDir, $Command)
}

function Get-TrustDevInitProfileLabel(
  [string]$Mode,
  [string]$Pack,
  [bool]$SinglePageTour
) {
  $label = $Mode
  if ($Mode -eq "blueprints") { $label += " / $Pack" }
  if ($SinglePageTour -and $Mode -eq "heuristic") { $label += " / singlePageTour" }
  return $label
}

function Write-TrustDevStackMarker([string]$TestAppDir, [string]$TestProject, [string]$SdkInitMode) {
  $markerPath = Join-Path $TestAppDir ".trustdev-stack.json"
  $flowSlug = ($TestProject -replace '_', '-').ToLowerInvariant()
  $flowVersionHint = if ($SdkInitMode -eq "heuristic" -and $SinglePageTour) { "$flowSlug-single-v1" } elseif ($SdkInitMode -eq "heuristic") { "$flowSlug-v1" } else { "$flowSlug-blueprints-v1" }
  $marker = @{
    testProject = $TestProject
    sdkInitMode = $SdkInitMode
    flowVersionHint = $flowVersionHint
    updatedAt = (Get-Date).ToString("o")
  } | ConvertTo-Json -Depth 3
  Set-Content -Path $markerPath -Value $marker -Encoding UTF8
}

function Invoke-NpmWithLog {
  param([Parameter(Mandatory = $true)][string[]]$NpmArguments)

  # npm envoie les warnings sur stderr ; avec $ErrorActionPreference Stop cela ne doit pas arreter le script.
  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & npm @NpmArguments 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) {
        Write-Host $_.ToString()
      } else {
        Write-Host $_
      }
    }
    return [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousEap
  }
}

function Install-TestAppSdkReact(
  [string]$TestAppDir,
  [string]$SdkReactDir,
  [string]$SdkTgzPath
) {
  if (-not (Test-Path -LiteralPath $SdkTgzPath -PathType Leaf)) {
    throw "Archive SDK introuvable apres npm pack: $SdkTgzPath"
  }

  $sdkPkgDir = Join-Path $TestAppDir "node_modules\@trustdev\onboarding-sdk-react"
  if (Test-Path -LiteralPath $sdkPkgDir) {
    Write-Host "Suppression de l ancien SDK dans node_modules..."
    Remove-Item -LiteralPath $sdkPkgDir -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
  }

  Push-Location $TestAppDir
  try {
    Write-Host "npm install --force `"$SdkTgzPath`""
    $exitCode = Invoke-NpmWithLog -NpmArguments @('install', '--force', $SdkTgzPath)
    if ($exitCode -eq 0) {
      Write-Host "SDK installe (exit 0)."
      return
    }

    Write-Warning "npm install tgz a echoue (code $exitCode). Nouvel essai via lien file vers les sources SDK..."
    $fileSpec = "file:$($SdkReactDir -replace '\\', '/')"
    Write-Host "npm install --force `"$fileSpec`""
    $exitCode = Invoke-NpmWithLog -NpmArguments @('install', '--force', $fileSpec)
    if ($exitCode -ne 0) {
      $msg = "npm install SDK a echoue (tgz et file). Verifie OneDrive sur node_modules. Reprends: npm install --force `"$SdkTgzPath`" dans $TestAppDir"
      throw $msg
    }
    Write-Host "SDK installe via file: (exit 0)."
  } finally {
    Pop-Location
  }
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
  $testAppDirCandidate = Resolve-FromScripts "..\..\e2e_sdk_tests\react\$TestProject"
  if (-not (Test-Path -LiteralPath $testAppDirCandidate -PathType Container)) {
    throw "Projet de test introuvable: '$TestProject' (chemin resolu: $testAppDirCandidate)."
  }
  $testAppDir = (Resolve-Path -LiteralPath $testAppDirCandidate).Path
  $testAppLeaf = Split-Path -Leaf $testAppDir
  if ($testAppLeaf -ne $TestProject) {
    throw "Mismatch TestProject: parametre '$TestProject' mais dossier resolu '$testAppLeaf' ($testAppDir)."
  }

  $tokenScriptPath = Resolve-FromScripts ".\refresh-sdk-token.ps1"
  $sdkTgzPath = Join-Path $sdkReactDir "trustdev-onboarding-sdk-react-0.1.0.tgz"
  $trustdevComponentPath = Join-Path $testAppDir "components\trustdev\trustdev-onboarding.tsx"
  $effectiveAppMode = $AppMode

  Write-Host ""
  Write-Host "Projet cible: $TestProject"
  Write-Host "Dossier absolu: $testAppDir"
  Write-Host "Fichier init: $trustdevComponentPath"
  Write-Host "URL locale: http://localhost:$AppPort"
  Write-Host "Astuce: tous les tests partagent la meme org API - chaque projet doit avoir un flowVersion distinct (filtre SDK)."

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
      throw "Le backend API (port 3020) nest pas demarre. Demarre-le puis relance le script avec -RefreshToken."
    }
  }

  if (-not $SkipSdkReinstall) {
    Invoke-Step "Build + pack SDK React local" {
      Push-Location $sdkReactDir
      try {
        $buildExit = Invoke-NpmWithLog -NpmArguments @('run', 'build')
        if ($buildExit -ne 0) { throw "npm run build a echoue (code $buildExit)." }
        $packExit = Invoke-NpmWithLog -NpmArguments @('pack')
        if ($packExit -ne 0) { throw "npm pack a echoue (code $packExit)." }
        if (-not (Test-Path -LiteralPath $sdkTgzPath -PathType Leaf)) {
          throw "Fichier attendu manquant: $sdkTgzPath"
        }
      } finally {
        Pop-Location
      }
    }

    Invoke-Step "Reinstall SDK dans $TestProject" {
      Install-TestAppSdkReact -TestAppDir $testAppDir -SdkReactDir $sdkReactDir -SdkTgzPath $sdkTgzPath
    }
  } else {
    Write-Host ""
    Write-Host "==> Build/pack/reinstall SDK ignores (-SkipSdkReinstall)"
    if (-not (Test-Path -LiteralPath $sdkTgzPath -PathType Leaf)) {
      Write-Warning "tgz absent: $sdkTgzPath - le projet utilisera le SDK deja dans node_modules."
    }
  }

  $sdkAlreadyInitialized = Test-TrustDevSdkInitialized -TestAppDir $testAppDir

  if ($SkipSdkInit) {
    Write-Host ""
    Write-Host "==> Initialisation TrustDev SDK ignoree (-SkipSdkInit)"
  } elseif ($sdkAlreadyInitialized -and -not $ForceSdkInit) {
    Write-Host ""
    Write-Host "==> Initialisation TrustDev SDK deja faite pour $TestProject (skip automatique)"
    Write-Host "Astuce: utilise -ForceSdkInit pour relancer init volontairement."
  } else {
    Invoke-Step "Initialisation TrustDev SDK dans $TestProject" {
      $localInitScript = Join-Path $testAppDir "node_modules\@trustdev\onboarding-sdk-react\scripts\init.js"
      $sourceInitScript = Join-Path $sdkReactDir "scripts\init.js"
      # Always prefer SDK source init.js (fresh template). node_modules can stay stale at 0.1.0.
      $initScript = if (Test-Path -Path $sourceInitScript -PathType Leaf) { $sourceInitScript } else { $localInitScript }

      if (-not (Test-Path -Path $initScript -PathType Leaf)) {
        throw "Script init TrustDev introuvable. Attendu: $sourceInitScript"
      }

      if ($ForceSdkInit) {
        Write-Host "ForceSdkInit: regeneration de $trustdevComponentPath"
        Write-Host "Script init: $initScript"
      }

      $initArgs = Build-TrustDevInitArgs -Mode $SdkInitMode -Pack $BlueprintPack -SinglePageTour:$SinglePageTour -ProjectDomain $ProjectDomain -TargetDir $testAppDir -NonInteractive:([bool]$SdkInitMode)
      if ([string]::IsNullOrWhiteSpace($SdkInitMode)) {
        Write-Warning "SdkInitMode non specifie : init interactif (choix heuristic/blueprints dans le terminal)."
      } else {
        $profileLabel = Get-TrustDevInitProfileLabel -Mode $SdkInitMode -Pack $BlueprintPack -SinglePageTour:$SinglePageTour.IsPresent
        Write-Host "Profil init: mode=$profileLabel"
      }

      Write-Host ('Lancement init: node "{0}" {1}' -f $initScript, ($initArgs -join ' '))
      & node $initScript @initArgs
      if ($LASTEXITCODE -ne 0) { throw "trustdev init a echoue." }
      if (Test-Path -LiteralPath $trustdevComponentPath) {
        Write-Host "OK fichier ecrit: $trustdevComponentPath (modifie: $((Get-Item -LiteralPath $trustdevComponentPath).LastWriteTime))"
      } else {
        throw "Init termine mais fichier introuvable: $trustdevComponentPath"
      }
    }
  }

  Write-TrustDevStackMarker -TestAppDir $testAppDir -TestProject $TestProject -SdkInitMode $(if ($SdkInitMode) { $SdkInitMode } else { "skipped" })

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
    $nodeOpts = [string]$env:NODE_OPTIONS
    $innerCmd = if ([string]::IsNullOrWhiteSpace($nodeOpts)) {
      $runCommand
    } else {
      ('set NODE_OPTIONS={0} && {1}' -f $nodeOpts, $runCommand)
    }
    $appCmd = Format-CmdExeChain -WorkDir $testAppDir -Command $innerCmd
    Start-Process -FilePath "cmd.exe" -ArgumentList "/k", $appCmd | Out-Null
    Write-Host "Next.js ($effectiveAppMode) en cours de demarrage sur http://localhost:$AppPort"
  }

  if ($StartTunnel) {
    Invoke-Step "Lancement tunnel (nouveau terminal)" {
      $tunnelCmd = Format-CmdExeChain -WorkDir $testAppDir -Command $TunnelCommand
      Start-Process -FilePath "cmd.exe" -ArgumentList "/k", $tunnelCmd | Out-Null
      Write-Host "Tunnel lance avec commande: $TunnelCommand"
    }
  }

  Write-Host ""
  Write-Host "Workflow termine."
  Write-Host "Astuce: attends 5-10s, puis ouvre localhost et l URL tunnel."
  if (-not [string]::IsNullOrWhiteSpace($SdkInitMode)) {
    $initLabel = Get-TrustDevInitProfileLabel -Mode $SdkInitMode -Pack $BlueprintPack -SinglePageTour:$SinglePageTour.IsPresent
    Write-Host "Init SDK: $initLabel"
  }
}
catch {
  Write-Error ('Echec restart-local-sdk-stack.ps1: ' + $_.Exception.Message)
  exit 1
}
