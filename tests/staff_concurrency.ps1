<#
Shows that a task can never be moved twice by two people acting at the same moment, and that task numbers never skip or repeat.
Two separate database sessions act on the same task:
  * "held" rounds:  session A starts the task and keeps its transaction open for two seconds; session B asks for the same move half
                    a second later. B must wait for A's row lock and then be refused ("already in progress"), with no extra history row.
  * "race" rounds:  both sessions start the same move at the same instant; exactly one wins, the other is refused.
  * "mixed" rounds: one session finishes the task while the other reassigns it, at the same instant. Either order is legal, but the
                    outcome must be consistent: the task's status is its latest history row, and a reassignment after "done" is refused.
  * "numbers":      two sessions create tasks at the same instant, several times; the numbers have no gaps and no duplicates.
This WRITES tasks (the history table is append-only, so they cannot be removed): run it on a scratch database only.
Usage: ./tests/staff_concurrency.ps1 [-Database nexus_st] [-Container nexus-pg-test] [-PgUser postgres] [-Rounds 3]
#>
param(
    [string]$Database = 'nexus_st',
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

# One administrator and two staff users of this script's own (a scratch database has no others to rely on).
$staffRole = Invoke-Sql "SELECT role_id FROM roles WHERE tenant_id = $tenant AND role_name = 'Staff'"
$adminId = Invoke-Sql "SELECT user_id FROM users WHERE tenant_id = $tenant AND user_type = 'admin' AND is_active ORDER BY user_id LIMIT 1"
if (-not $staffRole) { throw 'No Staff role: apply scripts 00-26 first.' }
$stamp = Get-Random -Minimum 1000 -Maximum 9999
if (-not $adminId) {
    # A freshly built database has no users (the first administrator is created by the API's seeding step).
    $adminRole = Invoke-Sql "SELECT role_id FROM roles WHERE tenant_id = $tenant AND role_name = 'Admin'"
    $adminId = Invoke-Sql "INSERT INTO users (tenant_id, user_name, full_name, password_hash, role_id, user_type) VALUES ($tenant, 'cc_admin$stamp', 'Concurrency Admin', 'x', $adminRole, 'admin') RETURNING user_id"
}
$staffA = Invoke-Sql "INSERT INTO users (tenant_id, user_name, full_name, password_hash, role_id, user_type) VALUES ($tenant, 'cc_a$stamp', 'Concurrency A', 'x', $staffRole, 'staff') RETURNING user_id"
$staffB = Invoke-Sql "INSERT INTO users (tenant_id, user_name, full_name, password_hash, role_id, user_type) VALUES ($tenant, 'cc_b$stamp', 'Concurrency B', 'x', $staffRole, 'staff') RETURNING user_id"

function Start-Session([string]$Name, [string]$Sql, [double]$DelaySeconds) {
    Start-Job -Name $Name -ArgumentList $Container, $PgUser, $Database, $Sql, $DelaySeconds -ScriptBlock {
        param($Container, $PgUser, $Database, $Sql, $DelaySeconds)
        if ($DelaySeconds -gt 0) { Start-Sleep -Milliseconds ([int]($DelaySeconds * 1000)) }
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $out = docker exec -i $Container psql -U $PgUser -d $Database -t -A -q -c $Sql 2>&1 | Out-String
        [pscustomobject]@{ Text = $out.Trim(); Ms = $watch.ElapsedMilliseconds }
    }
}

function New-Task([string]$Title) {
    return Invoke-Sql "SELECT fn_save_task($tenant, NULL, 'other', '$Title', NULL, NULL, NULL, $staffA, NULL, NULL, NULL, NULL, $adminId, NULL)"
}

function Get-Change([string]$Task, [string]$Status, [string]$Note, [int]$HoldSeconds) {
    $noteArg = if ($Note) { "'$Note'" } else { 'NULL' }
    $sql = "CALL sp_change_task_status($tenant, $Task, '$Status', $noteArg, $adminId, NULL); SELECT 'OK ' || '$Status'"
    if ($HoldSeconds -gt 0) { return "$sql; SELECT pg_sleep($HoldSeconds)" }
    return $sql
}

function Wait-Pair($A, $B) {
    $null = Wait-Job $A, $B -Timeout 60
    $resA = Receive-Job $A
    $resB = Receive-Job $B
    Remove-Job $A, $B -Force
    return @($resA, $resB)
}

$short = { param($t) $t = ($t -replace '\s+', ' '); if ($t.Length -gt 52) { $t.Substring(0, 52) } else { $t } }
$summary = @()

# held and race: the same move twice on one task.
foreach ($kind in @('held', 'race')) {
    for ($round = 1; $round -le $Rounds; $round++) {
        $task = New-Task "Concurrent $kind $round"
        if ($kind -eq 'held') {
            $a = Start-Session 'A' (Get-Change $task 'in_progress' '' 2) 0
            $b = Start-Session 'B' (Get-Change $task 'in_progress' '' 0) 0.5
        } else {
            $a = Start-Session 'A' (Get-Change $task 'in_progress' '' 0) 0
            $b = Start-Session 'B' (Get-Change $task 'in_progress' '' 0) 0
        }
        $res = Wait-Pair $a $b
        $outs = @($res[0].Text, $res[1].Text)
        $winners = @($outs | Where-Object { $_ -match 'OK in_progress' })
        $losers = @($outs | Where-Object { $_ -match 'already in progress' })
        $history = [int](Invoke-Sql "SELECT count(*) FROM task_status_history WHERE task_id = $task")
        $status = Invoke-Sql "SELECT status FROM tasks WHERE task_id = $task"
        # The loser of a held round must have waited for A's lock (A holds for 2 s, B starts 0.5 s in).
        $waited = if ($kind -eq 'held') { $res[1].Ms -ge 1000 } else { $true }
        $ok = ($winners.Count -eq 1) -and ($losers.Count -eq 1) -and ($history -eq 2) -and ($status -eq 'in_progress') -and $waited
        $summary += [pscustomobject]@{ Round = "$kind $round"; 'Session A' = (& $short $outs[0]); 'Session B' = (& $short $outs[1])
            'B ms' = $res[1].Ms; History = $history; Status = $status; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }) }
    }
}

# mixed: finish against reassign, no pause.
for ($round = 1; $round -le $Rounds; $round++) {
    $task = New-Task "Concurrent mixed $round"
    $null = Invoke-Sql (Get-Change $task 'in_progress' '' 0)
    $a = Start-Session 'A' (Get-Change $task 'done' 'Finished together' 0) 0
    $b = Start-Session 'B' "CALL sp_assign_task($tenant, $task, $staffB, $adminId, NULL); SELECT 'OK assigned'" 0
    $res = Wait-Pair $a $b
    $outs = @($res[0].Text, $res[1].Text)
    $done = $outs[0] -match 'OK done'
    $reassigned = $outs[1] -match 'OK assigned'
    $refused = $outs[1] -match 'cannot be changed|cannot'
    $status = Invoke-Sql "SELECT status FROM tasks WHERE task_id = $task"
    $assignee = Invoke-Sql "SELECT assigned_to FROM tasks WHERE task_id = $task"
    $latest = Invoke-Sql "SELECT new_status FROM task_status_history WHERE task_id = $task ORDER BY history_id DESC LIMIT 1"
    $history = [int](Invoke-Sql "SELECT count(*) FROM task_status_history WHERE task_id = $task")
    # Done always wins (it is a legal move from in progress in either order); the reassignment either happened first (3 rows,
    # new person) or was refused because the task was already done (3 rows, original person). The status is the latest row.
    $consistent = $done -and ($status -eq 'done') -and ($latest -eq 'done') -and ($history -eq 3 -or ($history -eq 4 -and $reassigned))
    if ($reassigned) { $consistent = $consistent -and ($assignee -eq $staffB) } else { $consistent = $consistent -and $refused -and ($assignee -eq $staffA) }
    $summary += [pscustomobject]@{ Round = "mixed $round"; 'Session A' = (& $short $outs[0]); 'Session B' = (& $short $outs[1])
        'B ms' = $res[1].Ms; History = $history; Status = $status; Result = $(if ($consistent) { 'PASS' } else { 'FAIL' }) }
}

# numbers: two creators at the same instant.
$before = Invoke-Sql "SELECT count(*) FROM tasks WHERE tenant_id = $tenant"
for ($round = 1; $round -le $Rounds; $round++) {
    $sql = "SELECT fn_save_task($tenant, NULL, 'other', 'Number race $round', NULL, NULL, NULL, $staffA, NULL, NULL, NULL, NULL, $adminId, NULL)"
    $a = Start-Session 'A' $sql 0
    $b = Start-Session 'B' $sql 0
    $res = Wait-Pair $a $b
    $ids = @($res[0].Text, $res[1].Text)
    $nos = @($ids | ForEach-Object { if ($_ -match '^\d+$') { Invoke-Sql "SELECT task_no FROM tasks WHERE task_id = $_" } else { $_ } })
    $pass = ($nos[0] -match '^TSK-\d{4}-\d{4}$') -and ($nos[1] -match '^TSK-\d{4}-\d{4}$') -and ($nos[0] -ne $nos[1])
    $summary += [pscustomobject]@{ Round = "numbers $round"; 'Session A' = $nos[0]; 'Session B' = $nos[1]
        'B ms' = $res[1].Ms; History = ''; Status = ''; Result = $(if ($pass) { 'PASS' } else { 'FAIL' }) }
}
$summary | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host

$year = Get-Date -Format yyyy
$counter = [int](Invoke-Sql "SELECT last_no FROM document_counters WHERE tenant_id = $tenant AND doc_type = 'TSK' AND doc_year = $year")
$count = [int](Invoke-Sql "SELECT count(*) FROM tasks WHERE tenant_id = $tenant AND task_no LIKE 'TSK-$year-%'")
$distinct = [int](Invoke-Sql "SELECT count(DISTINCT task_no) FROM tasks WHERE tenant_id = $tenant AND task_no LIKE 'TSK-$year-%'")
Write-Host "Task counter for $year = $counter; tasks numbered this year = $count (distinct $distinct)"
$gapFree = ($counter -eq $count) -and ($count -eq $distinct)
Write-Host ("No gaps and no duplicates: " + $(if ($gapFree) { 'PASS' } else { 'FAIL' }))

# The script's own two staff users keep tasks, so they stay (a scratch database); the verify script must still be clean.
Get-Content (Join-Path $PSScriptRoot '..\verify\verify_staff.sql') -Raw | docker exec -i $Container psql -U $PgUser -d $Database -v ON_ERROR_STOP=1 -q
Write-Host ("verify_staff.sql after the races: " + $(if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }))
if (($summary | Where-Object Result -ne 'PASS') -or -not $gapFree -or $LASTEXITCODE -ne 0) { exit 1 }
