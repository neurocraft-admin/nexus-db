<#
Shows that a customer can never end up with two active tickets, even when two submissions arrive at the same moment.
Two separate database sessions raise a ticket for the same customer:
  * "held" rounds:  session A creates the ticket and keeps its transaction open for two seconds; session B starts half a
                    second later, so it passes the friendly check (A has not committed yet), waits for the ticket-number
                    counter that A holds, and then meets uq_tickets_active_customer when A commits. B must get the
                    "already has an open ticket" answer, and its number must not be used up.
  * "race" rounds:  both sessions start at the same instant, with no pause; exactly one must win.
This WRITES tickets (the history table is append-only, so they cannot be removed): run it on a scratch database only.
Usage: ./tests/tickets_concurrency.ps1 [-Database nexus_tk] [-Container nexus-pg-test] [-PgUser postgres] [-Rounds 3]
#>
param(
    [string]$Database = 'nexus_tk',
    [string]$Container = 'nexus-pg-test',
    [string]$PgUser = 'postgres',
    [int]$Rounds = 3
)

$ErrorActionPreference = 'Stop'
$tenant = 1

function Invoke-Sql([string]$Sql) {
    $out = docker exec -i $Container psql -U $PgUser -d $Database -v ON_ERROR_STOP=1 -t -A -q -c $Sql 2>&1 | Out-String
    return $out.Trim()
}

$issueType = Invoke-Sql "SELECT issue_type_id FROM issue_types WHERE tenant_id = $tenant AND is_active ORDER BY sort_order LIMIT 1"
if (-not $issueType) { throw 'No active issue type: apply scripts 22 and 23 first.' }

function New-Customer([int]$Round, [string]$Kind) {
    $mobile = '9' + (Get-Random -Minimum 100000000 -Maximum 999999999)
    return Invoke-Sql "INSERT INTO customers (tenant_id, customer_name, mobile) VALUES ($tenant, 'Concurrency $Kind $Round', '$mobile') RETURNING customer_id"
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

function Get-Create([string]$CustomerId, [int]$HoldSeconds) {
    $create = "SELECT ticket_no FROM fn_create_ticket($tenant, $CustomerId, $issueType, NULL, 'Concurrent submission', 'portal', NULL, NULL, NULL, NULL, NULL)"
    if ($HoldSeconds -gt 0) { return "$create; SELECT pg_sleep($HoldSeconds)" }
    return $create
}

$rawNo = 0
# "raw" rounds skip fn_create_ticket and INSERT into the table directly (with a number of their own), so the unique
# index is shown on its own: the second session must get 23505 uq_tickets_active_customer.
function Get-RawInsert([string]$CustomerId, [int]$HoldSeconds) {
    $script:rawNo++
    $insert = "INSERT INTO tickets (tenant_id, ticket_no, customer_id, issue_type_id, description, source) VALUES ($tenant, 'TKT-RAW-$($script:rawNo)', $CustomerId, $issueType, 'Raw insert', 'portal') RETURNING ticket_no"
    if ($HoldSeconds -gt 0) { return "$insert; SELECT pg_sleep($HoldSeconds)" }
    return $insert
}

$summary = @()
foreach ($kind in @('held', 'race', 'raw')) {
    for ($round = 1; $round -le $Rounds; $round++) {
        $customer = New-Customer $round $kind
        $before = [int](Invoke-Sql "SELECT count(*) FROM tickets WHERE tenant_id = $tenant")
        if ($kind -eq 'held') {
            $a = Start-Session 'A' (Get-Create $customer 2) 0
            $b = Start-Session 'B' (Get-Create $customer 0) 0.5
        } elseif ($kind -eq 'raw') {
            $a = Start-Session 'A' (Get-RawInsert $customer 2) 0
            $b = Start-Session 'B' (Get-RawInsert $customer 0) 0.5
        } else {
            $a = Start-Session 'A' (Get-Create $customer 0) 0
            $b = Start-Session 'B' (Get-Create $customer 0) 0
        }
        $null = Wait-Job $a, $b -Timeout 60
        $resA = Receive-Job $a
        $resB = Receive-Job $b
        Remove-Job $a, $b -Force
        $outA = $resA.Text
        $outB = $resB.Text

        $tickets = [int](Invoke-Sql "SELECT count(*) FROM tickets WHERE customer_id = $customer")
        $active = [int](Invoke-Sql "SELECT count(*) FROM tickets WHERE customer_id = $customer AND status IN ('open', 'in_progress')")
        $history = [int](Invoke-Sql "SELECT count(*) FROM ticket_status_history h JOIN tickets t ON t.ticket_id = h.ticket_id WHERE t.customer_id = $customer")
        $after = [int](Invoke-Sql "SELECT count(*) FROM tickets WHERE tenant_id = $tenant")
        $winners = @($outA, $outB) | Where-Object { $_ -match '^TKT-(\d{4}-\d{4}|RAW-\d+)' }
        $loserPattern = if ($kind -eq 'raw') { 'uq_tickets_active_customer' } else { 'already has an open ticket' }
        $losers = @($outA, $outB) | Where-Object { $_ -match $loserPattern }
        # A refused submission that waited behind the other session's counter row (about 1.5 s) got past the friendly
        # check and was stopped by the unique index; this is what the "held" and "raw" rounds are for.
        $waited = if ($kind -eq 'race') { $true } else { $resB.Ms -ge 1000 }
        $ok = ($tickets -eq 1) -and ($active -eq 1) -and ($after - $before -eq 1) -and ($winners.Count -eq 1) -and ($losers.Count -eq 1) -and $waited `
            -and (($kind -eq 'raw') -or ($history -eq 1))
        $short = { param($t) $t = ($t -replace '\s+', ' '); if ($t.Length -gt 58) { $t.Substring(0, 58) } else { $t } }
        $summary += [pscustomobject]@{ Round = "$kind $round"; 'Session A' = (& $short $outA); 'Session B' = (& $short $outB)
            'B ms' = $resB.Ms; Tickets = $tickets; Active = $active; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }) }
    }
}

# The raw rows have no history row (they skipped the function), which verify_tickets.sql would flag, so they go.
$null = Invoke-Sql "DELETE FROM tickets WHERE ticket_no LIKE 'TKT-RAW-%'"
$summary | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host

# No number was used up by a loser: the counter equals the highest number given, and every number from 1 up exists.
$year = Get-Date -Format yyyy
$counter = [int](Invoke-Sql "SELECT last_no FROM document_counters WHERE tenant_id = $tenant AND doc_type = 'TKT' AND doc_year = $year")
$count = [int](Invoke-Sql "SELECT count(*) FROM tickets WHERE tenant_id = $tenant AND ticket_no LIKE 'TKT-$year-%'")
$distinct = [int](Invoke-Sql "SELECT count(DISTINCT ticket_no) FROM tickets WHERE tenant_id = $tenant AND ticket_no LIKE 'TKT-$year-%'")
Write-Host "Ticket counter for $year = $counter; tickets numbered this year = $count (distinct $distinct)"
$gapFree = ($counter -eq $count) -and ($count -eq $distinct)
Write-Host ("No gaps and no duplicates: " + $(if ($gapFree) { 'PASS' } else { 'FAIL' }))
if (($summary | Where-Object Result -ne 'PASS') -or -not $gapFree) { exit 1 }
