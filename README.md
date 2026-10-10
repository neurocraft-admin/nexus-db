# nexus-db

PostgreSQL scripts for NEXUS. There is no migration tool: scripts are applied by hand, in order, and each numbered script records itself in `deployment_log`.

```
NN_<module>_<change>.sql        numbered scripts (tables, indexes, seed, grants, guards); never edited once applied anywhere
StoredProcedures/<Module>/*.sql one file per function or procedure; re-run whenever the file changes
verify/verify_*.sql             run after every release; raises an error naming what is missing
scripts/apply-missing.ps1       applies only the numbered scripts deployment_log does not list, then functions and verify
scripts/apply-all.ps1           applies everything from 00 (fresh databases and test databases)
```

## Deploying scripts

Apply as the **postgres owner**, not `nexus_app` (that login has no DDL rights, on purpose). The rule is: apply **only the numbered scripts that `deployment_log` does not list yet**, in numeric order; then re-run the function files (they are re-runnable and may have changed); then the verify script; then check `deployment_log`.

### The helper (recommended)

```powershell
cd nexus-db
./scripts/apply-missing.ps1 -Database nexus -Container nexus-pg -ListOnly   # see what is missing, change nothing
./scripts/apply-missing.ps1 -Database nexus -Container nexus-pg             # apply it
```

It reads `deployment_log` from the database, applies only the numbered scripts that are not recorded there, re-applies every function file, runs the verify script and prints how many scripts the log now lists. A database with no `deployment_log` yet is treated as having nothing applied. It warns if a missing script is older than the newest applied one, and stops at the first error.

### By hand

```powershell
cd nexus-db
$container = 'nexus-pg'    # the Postgres container
$db        = 'nexus'       # the database

# 0. What has been applied already?
docker exec $container psql -U postgres -d $db -c "SELECT script_name, applied_at FROM deployment_log ORDER BY script_name"

# 1. Numbered scripts that are NOT in that list, in numeric order (00, 01, 02, ...)
$applied = docker exec $container psql -U postgres -d $db -tA -c "SELECT script_name FROM deployment_log"
Get-ChildItem *.sql | Where-Object { $_.Name -match '^\d\d_' -and $applied -notcontains $_.Name } | Sort-Object Name | ForEach-Object {
    Write-Host "Applying $($_.Name)"
    Get-Content -Raw $_.FullName | docker exec -i $container psql -U postgres -d $db -v ON_ERROR_STOP=1 -q
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}

# 2. Function and procedure files (always; they are re-runnable)
Get-ChildItem StoredProcedures -Recurse -Filter *.sql | Sort-Object FullName | ForEach-Object {
    Write-Host "Applying $($_.Name)"
    Get-Content -Raw $_.FullName | docker exec -i $container psql -U postgres -d $db -v ON_ERROR_STOP=1 -q
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}

# 3. Verify (raises an error if a script, table or function is missing)
Get-Content -Raw verify\verify_foundation.sql | docker exec -i $container psql -U postgres -d $db -v ON_ERROR_STOP=1

# 4. Check: there must be one row for every NN_*.sql file in this folder
docker exec $container psql -U postgres -d $db -c "SELECT script_name, applied_at FROM deployment_log ORDER BY script_name"
```

On a database that has no `deployment_log` yet, step 0 fails and `$applied` is empty, so step 1 applies everything from `00`.

### After every `git pull`

Apply again before starting the API. The API calls functions that later scripts add (for example `fn_get_user_by_id` from script 05). If a script has not been applied, requests fail with 500 and the API log shows `function ... does not exist`. The first thing to check is `deployment_log`: a missing row is the missing script.

### Notes

- Never edit a numbered script that has been applied anywhere; add the next number (the next free number is in `PROGRESS.md`). Function files can be edited and re-run.
- Use a separate container (for example `nexus-pg-test`) and database for experiments and tests; do not drop or recreate the shared one.
- After script `03_foundation_grants.sql` the `nexus_app` login still has no password. Set it yourself with `docker exec -it nexus-pg psql -U postgres -c "\password nexus_app"`; never put it in a script.
