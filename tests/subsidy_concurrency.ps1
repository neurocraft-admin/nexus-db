<#
Shows that two active subsidy slabs of a category can never overlap, even when two saves arrive at the same moment.
Two separate database sessions save overlapping slabs:
  * "held" rounds:  session A saves a slab and keeps its transaction open for two seconds; session B starts half a second later with a range that
                    overlaps A's. B must wait for A (they share a lock on the category) and then be refused with the overlap message.
  * "race" rounds:  both sessions start at the same instant with overlapping ranges; exactly one must win.
It writes and then deletes slabs (never touches an existing slab: it uses a category-wide range far above any real capacity, 9000 kW and up).
Run on a scratch database. Usage: ./tests/subsidy_concurrency.ps1 [-Database nexus_qf] [-Container nexus-pg-test] [-PgUser postgres] [-Rounds 3]
#>
param(
    [string]$Database = 'nexus_qf',
    [string]$Container = 'nexus-pg-test',
    [string]$PgUser = 'postgres',
    [int]$Rounds = 3
)
$ErrorActionPreference = 'Stop'
if ($Database -in @('nexus', 'postgres')) { throw "Refusing to use the database $Database" }

function Invoke-Sql([string]$Sql) {
    $out = docker exec -i $Container psql -U $PgUser -d $Database -v ON_ERROR_STOP=1 -t -A -q -c $Sql 2>&1 | Out-String
    return $out.Trim()
}

function Start-Session([string]$Name, [string]$Sql, [double]$DelaySeconds) {
    Start-Job -Name $Name -ArgumentList $Container, $PgUser, $Database, $Sql, $DelaySeconds -ScriptBlock {
        param($Container, $PgUser, $Database, $Sql, $DelaySeconds)
        if ($DelaySeconds -gt 0) { Start-Sleep -Milliseconds ([int]($DelaySeconds * 1000)) }
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $out = docker exec -i $Container psql -U $PgUser -d $Database -t -A -q -c $Sql 2>&1 | Out-String
        [pscustomobject]@{ Text = $out.Trim(); Ms = $watch.ElapsedMilliseconds }
    }
}

function Save-Slab([double]$From, [double]$To, [int]$Hold) {
    $call = "CALL sp_save_subsidy_slab(1, NULL, 'domestic', $From, $To, 1000, true, NULL, NULL)"
    if ($Hold -gt 0) { return "$call; SELECT pg_sleep($Hold)" }
    return $call
}

function Clear-TestSlabs { Invoke-Sql 'DELETE FROM subsidy_slabs WHERE tenant_id = 1 AND capacity_from_kw >= 9000' | Out-Null }

$failures = 0
function Check([string]$Label, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { Write-Host "PASS  $Label" } else { Write-Host "FAIL  $Label  $Detail"; $script:failures++ }
}

Clear-TestSlabs
for ($round = 1; $round -le $Rounds; $round++) {
    Clear-TestSlabs
    $a = Start-Session "A$round" (Save-Slab 9000 9100 2) 0
    $b = Start-Session "B$round" (Save-Slab 9050 9200 0) 0.5
    $ra = Receive-Job -Job $a -Wait; $rb = Receive-Job -Job $b -Wait
    Remove-Job $a, $b
    Check "held round ${round}: A saved" ($ra.Text -notmatch 'ERROR')
    Check "held round ${round}: B waited for A (took over a second)" ($rb.Ms -gt 1000) "took $($rb.Ms) ms"
    Check "held round ${round}: B was refused with the overlap message" ($rb.Text -match 'overlaps the active slab') $rb.Text
    Check "held round ${round}: one slab exists" ((Invoke-Sql 'SELECT count(*) FROM subsidy_slabs WHERE tenant_id = 1 AND capacity_from_kw >= 9000') -eq '1')
}
for ($round = 1; $round -le $Rounds; $round++) {
    Clear-TestSlabs
    $a = Start-Session "RA$round" (Save-Slab 9000 9100 0) 0
    $b = Start-Session "RB$round" (Save-Slab 9050 9200 0) 0
    $ra = Receive-Job -Job $a -Wait; $rb = Receive-Job -Job $b -Wait
    Remove-Job $a, $b
    $wins = @($ra, $rb | Where-Object { $_.Text -notmatch 'ERROR' }).Count
    Check "race round ${round}: exactly one save won" ($wins -eq 1) "$wins won"
    Check "race round ${round}: one slab exists" ((Invoke-Sql 'SELECT count(*) FROM subsidy_slabs WHERE tenant_id = 1 AND capacity_from_kw >= 9000') -eq '1')
}
Clear-TestSlabs
if ($failures -gt 0) { throw "$failures check(s) failed" }
Write-Host 'All concurrency checks passed.'
