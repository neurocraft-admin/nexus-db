<#
Applies only the numbered scripts that deployment_log does not list yet, then re-runs every function file
(they are re-runnable and may have changed), then the verify scripts. Use it on an existing database after
a git pull. For a brand-new database apply-all.ps1 does the same thing from 00.

Usage: ./scripts/apply-missing.ps1 [-Database nexus] [-Container nexus-pg] [-PgUser postgres] [-ListOnly]
  -ListOnly   show what would be applied and change nothing

Run as the postgres owner. It stops at the first error.
#>
param(
    [string]$Database = 'nexus',
    [string]$Container = 'nexus-pg',
    [string]$PgUser = 'postgres',
    [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Invoke-Psql([string]$Sql) {
    $result = docker exec $Container psql -U $PgUser -d $Database -v ON_ERROR_STOP=1 -tA -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "Could not query the database '$Database' in container '$Container'." }
    return $result
}

function Invoke-SqlFile([System.IO.FileInfo]$File) {
    Write-Host "Applying $($File.FullName.Substring($root.Length + 1))"
    Get-Content -Raw -Encoding UTF8 $File.FullName |
        docker exec -i -e 'PGOPTIONS=-c client_min_messages=warning' $Container psql -U $PgUser -d $Database -v ON_ERROR_STOP=1 -q -o NUL
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($File.Name)" }
}

# What the database says has been applied. A database that has no deployment_log yet has applied nothing.
$logExists = (Invoke-Psql "SELECT to_regclass('public.deployment_log') IS NOT NULL") -eq 't'
$applied = @()
if ($logExists) {
    $applied = @(Invoke-Psql 'SELECT script_name FROM deployment_log ORDER BY script_name' | Where-Object { $_ })
}

$numbered = @(Get-ChildItem -Path $root -Filter '*.sql' -File | Where-Object { $_.Name -match '^\d\d_' } | Sort-Object Name)
$missing = @($numbered | Where-Object { $applied -notcontains $_.Name })
$functions = @(Get-ChildItem -Path (Join-Path $root 'StoredProcedures') -Filter '*.sql' -File -Recurse | Sort-Object FullName)
$verify = @(Get-ChildItem -Path (Join-Path $root 'verify') -Filter '*.sql' -File | Sort-Object Name)

Write-Host "Database '$Database' in '$Container': $($applied.Count) script(s) recorded, $($missing.Count) missing."
foreach ($file in $numbered | Where-Object { $applied -contains $_.Name }) { Write-Host "  already applied: $($file.Name)" }
foreach ($file in $missing) { Write-Host "  MISSING:         $($file.Name)" }

# A script older than one that is already applied was skipped at some point; applying it now is usually
# right (scripts are re-runnable) but worth seeing.
$newestApplied = ($applied | Sort-Object | Select-Object -Last 1)
$late = @($missing | Where-Object { $newestApplied -and $_.Name -lt $newestApplied })
if ($late.Count -gt 0) {
    Write-Warning "These scripts are older than the newest applied script ($newestApplied): $($late.Name -join ', ')"
}

if ($ListOnly) {
    Write-Host 'ListOnly: nothing was changed.'
    return
}

foreach ($file in $missing) { Invoke-SqlFile $file }
Write-Host "Re-applying $($functions.Count) function file(s) and verifying."
foreach ($file in @($functions) + @($verify)) { Invoke-SqlFile $file }

$rows = Invoke-Psql 'SELECT count(*) FROM deployment_log'
Write-Host "Done: $Database now lists $rows script(s) in deployment_log; $($numbered.Count) numbered script(s) exist."
