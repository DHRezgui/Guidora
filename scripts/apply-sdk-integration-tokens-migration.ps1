# Applies sdk_integration_tokens table to local Postgres (docker-compose.dev).
param(
  [string]$ContainerName = "trustdev_onboarding_sdk-postgres-1",
  [string]$DbName = "onboarding",
  [string]$DbUser = "admin"
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlPath = Join-Path $scriptRoot "..\backend\src\auth\migrations\add-sdk-integration-tokens-table.sql"
$sqlPath = [System.IO.Path]::GetFullPath($sqlPath)

if (-not (Test-Path $sqlPath)) {
  throw "SQL file not found: $sqlPath"
}

Write-Host "Applying migration from $sqlPath to container $ContainerName ..."
Get-Content -Path $sqlPath -Raw | docker exec -i $ContainerName psql -U $DbUser -d $DbName
Write-Host "Done."
