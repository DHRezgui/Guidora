$ErrorActionPreference = 'Stop'
$sql = Join-Path $PSScriptRoot '..\backend\src\user\migrations\add-super-admin-role.sql'
Get-Content $sql | docker exec -i trustdev_onboarding_sdk-postgres-1 psql -U admin -d onboarding
Write-Host 'Migration SUPER_ADMIN appliquée.'
