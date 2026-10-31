# nexus-db

PostgreSQL scripts for NEXUS. There is no migration tool: scripts are applied by hand, in order, and each numbered script records itself in `deployment_log`.

```
NN_<module>_<change>.sql        numbered scripts (tables, indexes, seed, grants, guards); never edited once applied anywhere
StoredProcedures/<Module>/*.sql one file per function or procedure; re-run whenever the file changes
verify/verify_*.sql             run after every release; raises an error naming what is missing
scripts/apply-missing.ps1       applies only the scripts missing from deployment_log, in numeric order, then functions and verify
scripts/apply-all.ps1           applies everything from 00 (fresh databases and test databases)
```

## Deploying scripts

Apply as the **postgres owner**, not `nexus_app` (that login has no DDL rights, on purpose). The rule is: apply **only the scripts missing from `deployment_log`, in numeric order**; then re-run the function files (they are re-runnable and may have changed); then the verify script; then check `deployment_log`.

### The helper (recommended)

```powershell
cd nexus-db
./scripts/apply-missing.ps1 -Database nexus -Container nexus-pg -ListOnly   # see what is missing, change nothing
./scripts/apply-missing.ps1 -Database nexus -Container nexus-pg             # apply it
```

It reads `deployment_log` from the database, applies only the scripts missing from it, in numeric order, re-applies every function file, runs the verify script and prints how many scripts the log now lists. A database with no `deployment_log` yet is treated as having nothing applied. It warns if a missing script is older than the newest applied one, and stops at the first error.

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

# 3. Verify, every module's verify script (raises an error if a script, table or function is missing)
Get-ChildItem verify -Filter *.sql | Sort-Object Name | ForEach-Object {
    Get-Content -Raw $_.FullName | docker exec -i $container psql -U postgres -d $db -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "Verification failed: $($_.Name)" }
}

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

## Inventory (module 5)

- **Stock changes only through the ledger.** `items.current_stock` is changed only together with a `stock_movements` row, by `sp_stock_in`, `sp_stock_out`, `sp_adjust_stock` or `sp_record_purchase`. The ledger is append-only (a trigger refuses UPDATE, DELETE and TRUNCATE), and `SELECT * FROM vw_item_stock_check WHERE difference <> 0` must return no rows.
- **Opening stock** is entered as an adjustment (Admin, with a note such as "Opening stock"). **Set the item's cost price first**: the adjustment row records the item's cost price at that moment, and that is the value the ledger keeps.
- **Stock never goes negative** (`ck_items_stock_not_negative`). A stock-out or adjustment that would do so raises `NX411` with the item, what is available and what was asked for.
- **Units** are master data in the `units` table (nos, m, kg, ltr, pack, box, set, pair, roll). To add one for now: `INSERT INTO units (tenant_id, unit_code, unit_name, sort_order) VALUES (1, 'bag', 'Bag', 100);`
- **Other modules** (order fulfilment) call `sp_stock_out` from inside their own procedure so a multi-line order commits or rolls back as one.

## Packages (module 4)

- **A package is a stock-item bundle sold at one typed-in, tax-inclusive price** (`package_price`, above 0). There is no GST column, rate or tax split anywhere. A price below the component cost is a warning for the person, never a block.
- **Lines are stock items only** (`item_id` and a quantity of up to 3 decimals). Name, unit, cost, selling price and stock are read live from `items`; labour is a custom quotation line, not a package line.
- **Cost is live, price is fixed.** `vw_package_summary` computes the component cost from current item cost prices (sum of `round(quantity x cost_price, 2)`). `component_cost_at_save` keeps the figure from the last save so a screen can say the cost has moved. Quotations copy the price when issued.
- **Availability only reads stock** (`fn_get_package_availability`: required, available, short by, complete sets possible). It never reserves, deducts or blocks. Stock leaves only through order fulfilment (`sp_stock_out`), where the strict no-negative-stock block applies; fulfilment gets the components from `fn_get_package_components`.
- **A deactivated component** is not blocked: the package is flagged (`has_inactive_component`, "Needs attention"), saving it is refused until the item is replaced, and fulfilment fails with a conflict naming the item.

## Quotations and orders (module 3)

- **Tax-inclusive, no GST columns.** `quotation_lines.line_total = round(quantity x unit_price, 2)`, `subtotal` is the sum of the rounded line totals and `total_amount = subtotal - discount_amount` (one flat discount, never above the subtotal). The CHECK constraints are the safety net; `sp_save_quotation` does the arithmetic and the client's figures are never trusted. Each line copies its description, unit and price, so changing an item or package later never changes an issued quotation or an order.
- **Status moves** are enforced in `sp_set_quotation_status`: draft to sent or rejected; sent to approved or rejected. `expired` is set only by `sp_expire_quotations` (sent quotations whose `valid_until` is before today in `business_time_zone`; an approved one stays convertible) and `converted` only by `fn_convert_quotation_to_order`. Only a draft can be edited. Every change writes an append-only row to `quotation_status_log` or `order_status_log`.
- **Convert** needs an approved quotation with an active customer. The quotation row is locked and `uq_orders_quotation` allows one order per quotation, so a double click makes one order and the second call is refused (NX409, naming the order). A cancelled order does not free the quotation: revise it with `sp_duplicate_quotation` ("Duplicate as new draft", linked by `revision_of_id`).
- **Stock is deducted only by `sp_fulfil_order`**, in one transaction: lock the order, the customer, then the items in id order; check the whole order (`sp_check_order_stock`: inactive items NX409, any item short NX411, every problem named; `fn_get_order_shortages` returns the list as rows); `sp_stock_out` per item line and per package component; for `credit`, `sp_record_credit_charge` for the order total; then mark the order fulfilled. Any failure rolls back stock, ledger and status. **There is no credit limit anywhere** (customers have no limit column and the charge never refuses), so a credit order is accepted whatever the customer owes.
- **Quotations only warn about stock**: `fn_get_lines_availability` adds up what a set of lines needs per item (item lines plus package components) and says "short by N". It never blocks or deducts.
- **Letterhead settings** (script 16, all start empty): `company_name`, `company_address`, `company_phone`, `company_bank_details`, `quotation_footer_note`. There is no GSTIN setting.
- Order numbers are `ORD-yyyy-nnnn` and quotation numbers `QTN-yyyy-nnnn`, from `fn_next_document_no`.
