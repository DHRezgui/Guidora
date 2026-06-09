# Applies organization_journey_blueprints table (idempotent).
# Usage: .\scripts\apply-journey-blueprints-migration.ps1
# Env: DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME (defaults match local stack)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$sqlFile = Join-Path $root 'backend\src\guided-tour\migrations\add-organization-journey-blueprints-table.sql'

if (-not (Test-Path $sqlFile)) {
  Write-Error "Migration file not found: $sqlFile"
}

$hostName = if ($env:DB_HOST) { $env:DB_HOST } else { 'localhost' }
$port = if ($env:DB_PORT) { $env:DB_PORT } else { '5432' }
$user = if ($env:DB_USER) { $env:DB_USER } else { 'postgres' }
$db = if ($env:DB_NAME) { $env:DB_NAME } else { 'trustdev_onboarding' }

Write-Host "Applying journey blueprints migration to $db on ${hostName}:${port} ..."

if ($env:DB_PASSWORD) {
  $env:PGPASSWORD = $env:DB_PASSWORD
}

& psql -h $hostName -p $port -U $user -d $db -f $sqlFile

Write-Host 'Done. Verify: \dt organization_journey_blueprints'
