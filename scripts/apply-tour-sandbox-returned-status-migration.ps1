# Applies tour_sandbox_status enum value 'returned' for admin return-to-developer workflow.
param(
  [string]$ContainerName = "trustdev_onboarding_sdk-postgres-1",
  [string]$DbName = "onboarding",
  [string]$DbUser = "admin"
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlPath = Join-Path $scriptRoot "..\backend\src\guided-tour\migrations\add-tour-sandbox-returned-status.sql"
$sqlPath = [System.IO.Path]::GetFullPath($sqlPath)

if (-not (Test-Path $sqlPath)) {
  throw "SQL file not found: $sqlPath"
}

Write-Host "Applying migration from $sqlPath to container $ContainerName ..."
Get-Content -Path $sqlPath -Raw | docker exec -i $ContainerName psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1
Write-Host "Done."
