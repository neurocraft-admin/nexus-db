<#
Applies every database script in order against the nexus-pg container:
numbered scripts, then function files, then the verify scripts. Stops at the first error.
Usage: ./scripts/apply-all.ps1 [-Database nexus] [-Container nexus-pg] [-PgUser postgres]
#>
param(
    [string]$Database = 'nexus',
    [string]$Container = 'nexus-pg',
    [string]$PgUser = 'postgres'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Invoke-SqlFile([System.IO.FileInfo]$File) {
    Write-Host "Applying $($File.FullName.Substring($root.Length + 1))"
    Get-Content -Raw -Encoding UTF8 $File.FullName |
        docker exec -i -e 'PGOPTIONS=-c client_min_messages=warning' $Container psql -U $PgUser -d $Database -v ON_ERROR_STOP=1 -q -o NUL
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($File.Name)" }
}

$numbered = Get-ChildItem -Path $root -Filter '*.sql' -File | Where-Object { $_.Name -match '^\d\d_' } | Sort-Object Name
$functions = Get-ChildItem -Path (Join-Path $root 'StoredProcedures') -Filter '*.sql' -File -Recurse |
    Sort-Object FullName
$verify = Get-ChildItem -Path (Join-Path $root 'verify') -Filter '*.sql' -File | Sort-Object Name

foreach ($file in @($numbered) + @($functions) + @($verify)) { Invoke-SqlFile $file }
Write-Host "Done: $Database"
