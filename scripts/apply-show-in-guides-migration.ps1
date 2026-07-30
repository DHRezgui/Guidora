# Applies show_in_guides column for curated Aide Guides catalog.
param(
  [string]$ContainerName = "trustdev_onboarding_sdk-postgres-1",
  [string]$DbName = "onboarding",
  [string]$DbUser = "admin",
  [switch]$EnableDemoPortfolioPulse
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlPath = Join-Path $scriptRoot "..\backend\src\guided-tour\migrations\add-show-in-guides.sql"
$sqlPath = [System.IO.Path]::GetFullPath($sqlPath)

if (-not (Test-Path $sqlPath)) {
  throw "SQL file not found: $sqlPath"
}

Write-Host "Applying migration from $sqlPath to container $ContainerName ..."
Get-Content -Path $sqlPath -Raw | docker exec -i $ContainerName psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1

if ($EnableDemoPortfolioPulse) {
  Write-Host "Enabling show_in_guides for Portfolio Pulse demo tours..."
  $demoSql = @"
UPDATE guided_tours
SET show_in_guides = true
WHERE is_active = true
  AND (
    name ILIKE '%Portfolio Pulse%'
    OR name ILIKE '%vue exécutive%'
  );
"@
  $demoSql | docker exec -i $ContainerName psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1
}

Write-Host "Done."
