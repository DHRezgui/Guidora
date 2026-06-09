# Applies backfill-admin-legacy-guided-tours.sql via the dev Postgres container.
# Usage (from trustdev_onboarding_sdk): .\scripts\apply-backfill-admin-legacy-tours.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$sqlFile = Join-Path $root 'backend\src\guided-tour\migrations\backfill-admin-legacy-guided-tours.sql'
$container = if ($env:POSTGRES_CONTAINER) { $env:POSTGRES_CONTAINER } else { 'trustdev_onboarding_sdk-postgres-1' }
$dbUser = if ($env:DB_USER) { $env:DB_USER } else { 'admin' }
$dbName = if ($env:DB_NAME) { $env:DB_NAME } else { 'onboarding' }

if (-not (Test-Path $sqlFile)) {
  Write-Error "Migration file not found: $sqlFile"
}

Write-Host "Applying admin legacy tour backfill via container $container ..."
Get-Content -Raw $sqlFile | docker exec -i $container psql -U $dbUser -d $dbName -v ON_ERROR_STOP=1
Write-Host 'Done. Verify with:'
Write-Host "  docker exec $container psql -U $dbUser -d $dbName -c `"SELECT name, sandbox_status, trigger_conditions->'contextualEngine'->>'publishedByRole' AS pub_role FROM guided_tours WHERE created_by = (SELECT id FROM users WHERE email = 'dhia.rezgui@ensi-uma.tn');`""
