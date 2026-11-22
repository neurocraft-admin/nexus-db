<#
Migration test for the quotation format (scripts 29-32): what happens to a database that already holds real quotations.
It builds a scratch database from the PREVIOUS release (a checkout of nexus-db before this module, given with -BaselinePath), writes legacy rows with
that release's functions (tests/quotation_format_migration_seed.sql), applies THIS checkout on top, checks the result
(tests/quotation_format_migration_check.sql), applies it a second time, and checks that nothing changed.
Scratch databases only: it refuses a database called nexus. Usage (from the nexus-db folder):
  git worktree add ../nexus-db-baseline f14d57d        # the release before the module
  ./tests/quotation_format_migration.ps1 -BaselinePath ../nexus-db-baseline [-Database nexus_qf_mig] [-Container nexus-pg-test]
  git worktree remove ../nexus-db-baseline
#>
param(
    [Parameter(Mandatory = $true)][string]$BaselinePath,
    [string]$Database = 'nexus_qf_mig',
    [string]$Container = 'nexus-pg-test',
    [string]$PgUser = 'postgres'
)
$ErrorActionPreference = 'Stop'
if ($Database -in @('nexus', 'postgres')) { throw "Refusing to use the database $Database" }
$root = Split-Path -Parent $PSScriptRoot
$baseline = (Resolve-Path $BaselinePath).Path

function Invoke-Psql([string]$Sql, [string]$Db) {
    docker exec -i $Container psql -U $PgUser -d $Db -v ON_ERROR_STOP=1 -q -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "psql failed: $Sql" }
}
function Invoke-SqlFile([string]$Path) {
    Get-Content -Raw -Encoding UTF8 $Path | docker exec -i $Container psql -U $PgUser -d $Database -v ON_ERROR_STOP=1 -q -t
    if ($LASTEXITCODE -ne 0) { throw "Failed: $Path" }
}

Write-Host "1. Baseline database from $baseline"
Invoke-Psql "DROP DATABASE IF EXISTS $Database WITH (FORCE)" 'postgres'
Invoke-Psql "CREATE DATABASE $Database" 'postgres'
& (Join-Path $baseline 'scripts/apply-all.ps1') -Database $Database -Container $Container -PgUser $PgUser | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'The baseline did not apply' }

Write-Host '2. Legacy data, written with the previous release''s functions'
Invoke-SqlFile (Join-Path $PSScriptRoot 'quotation_format_migration_seed.sql')

Write-Host '3. This checkout applied on top, then checked'
& (Join-Path $root 'scripts/apply-all.ps1') -Database $Database -Container $Container -PgUser $PgUser | Out-Null
Invoke-SqlFile (Join-Path $PSScriptRoot 'quotation_format_migration_check.sql')

Write-Host '4. Applied a second time, checked again (the migration must change nothing)'
& (Join-Path $root 'scripts/apply-all.ps1') -Database $Database -Container $Container -PgUser $PgUser | Out-Null
Invoke-SqlFile (Join-Path $PSScriptRoot 'quotation_format_migration_check.sql')
Write-Host 'Migration test passed.'
