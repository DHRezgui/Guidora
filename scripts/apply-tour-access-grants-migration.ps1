# Applies tour access grants (guided_tour_access_grants, in_collaboration).
param(
  [string]$ContainerName = "trustdev_onboarding_sdk-postgres-1",
  [string]$DbName = "onboarding",
  [string]$DbUser = "admin"
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlPath = Join-Path $scriptRoot "..\backend\src\guided-tour\migrations\add-tour-access-grants.sql"
$sqlPath = [System.IO.Path]::GetFullPath($sqlPath)

if (-not (Test-Path $sqlPath)) {
  throw "SQL file not found: $sqlPath"
}

Write-Host "Applying migration from $sqlPath to container $ContainerName ..."
Get-Content -Path $sqlPath -Raw | docker exec -i $ContainerName psql -U $DbUser -d $DbName
Write-Host "Done."
