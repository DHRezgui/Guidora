param(
  [switch]$RefreshToken,
  [string]$Email,
  [string]$Password,
  [ValidateSet("prod", "dev")]
  [string]$AppMode = "prod",
  [int]$AppPort = 3000,
  [switch]$KillBackendPort3020,
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

try {
  $repoRoot = Resolve-FromScripts ".."
  $sdkReactDir = Resolve-FromScripts "..\sdks\react"
  $testAppDir = Resolve-FromScripts "..\..\e2e_sdk_tests\react\test_1"
  $tokenScriptPath = Resolve-FromScripts ".\refresh-sdk-token.ps1"
  $sdkTgzPath = Join-Path $sdkReactDir "trustdev-onboarding-sdk-react-0.1.0.tgz"

  Invoke-Step "Nettoyage des process existants (ports 3000, 3001)" {
    $portsToKill = @(3000, 3001)
    if ($KillBackendPort3020) {
      $portsToKill += 3020
    }
    Stop-PortListeners -Ports $portsToKill
    Stop-TunnelProcesses
  }

  if ($RefreshToken) {
    if ([string]::IsNullOrWhiteSpace($Email) -or [string]::IsNullOrWhiteSpace($Password)) {
      throw "Utilise -Email et -Password quand -RefreshToken est active."
    }
    if (-not (Test-PortListening -Port 3020)) {
      throw "Le backend API (port 3020) n'est pas demarre. Demarre-le puis relance le script avec -RefreshToken."
    }

    Invoke-Step "Refresh token SDK" {
      & $tokenScriptPath -Email $Email -Password $Password
      if (-not $?) { throw "Echec refresh-sdk-token.ps1" }
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

  Invoke-Step "Reinstall SDK dans test_1" {
    Push-Location $testAppDir
    try {
      npm install $sdkTgzPath
      if ($LASTEXITCODE -ne 0) { throw "npm install tgz a echoue." }
    } finally {
      Pop-Location
    }
  }

  if ($AppMode -eq "prod") {
    Invoke-Step "Build test_1 (mode prod)" {
      Push-Location $testAppDir
      try {
        npm run build
        if ($LASTEXITCODE -ne 0) { throw "npm run build (test_1) a echoue." }
      } finally {
        Pop-Location
      }
    }
  }

  Invoke-Step "Lancement Next $AppMode (nouveau terminal)" {
    $runCommand = if ($AppMode -eq "prod") { "npm run start" } else { "npm run dev" }
    $appCmd = "cd /d `"$testAppDir`" && $runCommand"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/k", $appCmd | Out-Null
    Write-Host "Next.js ($AppMode) en cours de demarrage sur http://localhost:$AppPort"
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
