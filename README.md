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

## Leads (module 1)

- **Open lead = active and not Won/Lost.** `uq_leads_open_mobile` (tenant, mobile, only where `is_active AND NOT is_closed`) lets one open lead hold a mobile at a time; a closed or deactivated lead frees it. `is_closed` is kept on the lead (set with the status) because an index cannot look at another table. `fn_save_lead` checks first for a readable message (NX409, naming the lead) and maps a race's unique violation to the same answer.
- **Mobiles** are reduced by `fn_normalise_mobile` (spaces and dashes out, `+91`, `91` before 10 digits or a leading `0` removed) exactly as the API's `MobileNumber.Normalize` does, and must then match `^[6-9][0-9]{9}$`. The test `The_database_reduces_a_mobile_exactly_as_the_API_does` and the API's `MobileNumberTests` hold the two together.
- **Statuses and sources are rows.** The pipeline (New, Contacted, Qualified, Negotiation, Won, Lost) is changed by script only; Won is reached only by `fn_convert_lead`, Lost needs a reason (kept on the lead and in its history row). Sources (Facebook, Instagram, Walk-in, Referral, Phone) can be added with `sp_save_lead_source`; `source_code`, `external_ref` and `source_detail` leave room for Meta capture later without a schema change.
- **History** is `lead_activities`, append-only (trigger). Exactly one row per change; a change that changes nothing writes nothing.
- **Staff see only their leads.** Every function takes `p_visible_to` (the staff user's id, NULL for an admin); a lead outside it behaves as if it did not exist.
- **Convert** runs in one transaction under a lock on the lead alone (locking a join made a waiting caller find nothing): find or create the customer by mobile, mark the lead Won, one history row, and set the customer on that lead's quotations that have none (an audit row in `quotation_status_log` on each). A deactivated customer holding the mobile refuses the conversion.
- **Import** (`fn_check_import_rows` previews and writes nothing; `fn_import_leads` validates again and saves each row in its own sub-transaction, so a bad row never blocks the others). The caller's parsing is never trusted. At most 1000 rows.
- **Script 17** adds the foreign key from `quotations.lead_id` to `leads`. It stops with a message if any quotation points at a lead that does not exist: run `SELECT count(*) FROM quotations WHERE lead_id IS NOT NULL` first (expected 0), and fix any rows before applying.

## Company profile

- **One row per tenant** in `company_profile` (`uq_company_profile_tenant`): names, tagline, address, contacts, GSTIN, PAN, state code, bank and UPI details, "other payment details", the quotation footer note and terms. Every field is optional; a blank is stored as NULL. `fn_get_company_profile` always returns exactly one row (all NULL for a tenant that never saved one), so callers need no "no profile" case.
- **Saving** is `sp_save_company_profile(tenant, json, user)`: the whole profile as one JSON document (request names in camelCase), validated first by `sp_check_company_profile`, so a wrong field names itself (SQLSTATE 22023, COLUMN = the request field). GSTIN, PAN and IFSC are stored upper-cased. The table's own CHECKs repeat the same patterns as a safety net. The state code must match the first two digits of the GSTIN when both are given.
- **GSTIN, PAN and the state code are labels only.** Amounts stay tax-inclusive and nothing is calculated from them (amendment to the 2026-10-17 "no GST anywhere" decision).
- **The logo is a file**, not a column: the table keeps only its random stored name and type (PNG or JPEG), set by `sp_set_company_logo`, which returns the previous file name so the API can delete it. The folder is `Company:LogoPath` (production `/var/nexus/company` on a named volume): **backups must include that volume as well as the database.**
- **Public view:** `fn_get_public_company` returns the display name (else the legal name) and a has-logo flag, nothing else. It is the only function an anonymous endpoint may read for the company; bank details, GSTIN and every other field never go out on a public endpoint.
- **Migration:** script 20 copies the five old letterhead rows of `app_settings` once (name into both names, address into line 1, phone, the free-text bank details into "other payment details", the footer note). It stops with a message naming a setting that will not fit its new column. It never overwrites an existing profile row, and it leaves the old rows in place: script 24, applied after the quotation PDF has been confirmed on the new table, drops them.
- **Permission:** the `company_profile` resource (view and update, no create or delete) goes to the Admin role only, with the Administration > Company menu entry (script 21).

## Tickets and the support portal (module 7)

Scripts 22 (schema, seeds) and 23 (resources, menu, permissions); functions in `StoredProcedures/Tickets/`; `verify/verify_tickets.sql` runs with the others. Script 24 is reserved for the later drop of the old letterhead settings (see Company profile).

- **Tables:** `issue_types` (master data, five seeded; there is deliberately **no "Other" row**: Other is free text in `other_issue_text`, and `ck_tickets_issue` needs exactly one of the two), `tickets`, `ticket_status_history` (append-only by trigger) and `ticket_attachments`.
- **Numbers** are `TKT-yyyy-nnnn` from `fn_next_document_no`: four digits, reset each year. The number is taken inside `fn_create_ticket`'s transaction, so a refused ticket uses none up.
- **One active ticket per customer:** active = `open` or `in_progress`. `sp_assert_no_active_ticket` is the friendly check (NX409; the message and HINT carry the existing ticket number, which the portal shows; HINT and not DETAIL because Npgsql redacts DETAIL); the partial unique index `uq_tickets_active_customer` is the guarantee when two submissions arrive together, and `fn_create_ticket` maps that race to the same answer. A reopen (resolved to in progress) that would collide is refused the same way. Resolved and closed tickets do not block a new one.
- **Status rules** are in `sp_check_ticket_status_move`: open to in progress; in progress to resolved; resolved to closed; resolved to in progress (reopen, from Resolved only); open to closed (needs a note). Closed is final, and a ticket cannot stay where it is. `sp_change_ticket_status` locks the row first, so two people acting together are decided one after the other. `resolved_at` is cleared on a reopen; `ck_tickets_stamps` keeps the time stamps in step with the status.
- **Assignment** (`sp_assign_ticket`) does not change the status. It writes a history row whose old and new status are the same and whose `assigned_to` is set (`ck_ticket_history_assignment`). Staff and admin users can both be assigned; a closed ticket cannot be. **Only non-staff users may assign or reassign:** `sp_assign_ticket` refuses a staff caller (`p_visible_to` not NULL) with SQLSTATE 42501, even for their own ticket. Staff can still change the status of their own tickets.
- **Staff see only their own tickets:** every read and write function takes `p_visible_to` (the staff user's id, NULL for everyone else) and treats a ticket outside it as not found. A ticket is visible to a staff user when it is **assigned to them or raised by them** (module 11: the front desk can follow the tickets it raised). An unassigned ticket raised on the portal is visible to no staff user. **Only the person a ticket is assigned to can change its status:** the creator of someone else's ticket gets SQLSTATE 42501 (a 403) from `sp_change_ticket_status`, not "not found".
- **Creating** (`fn_create_ticket`) writes the ticket, its first history row and the optional attachment row in one transaction. The file itself is stored by the API under `Tickets:AttachmentPath` (production `/var/nexus/attachments`, a named volume that **backups must include**). Sizes and types are table CHECKs (PDF, JPEG, PNG, up to 5 MB); the API checks the file's own bytes first.
- **The portal's Check Status** (`fn_get_open_tickets_by_mobile`) returns five columns only: number, issue text, status, the technician's FIRST name and the raised date. The portal's lookup reuses `fn_get_customer_by_mobile` (Customers).
- **Error codes** as elsewhere: 22023 invalid field (COLUMN names the request field), P0002 not found, NX409 rule conflict, 23505 on a duplicate issue type name (`uq_issue_types_tenant_name`).
- **Tests:** `tests/test_tickets.sql` (212 checks in one rolled-back transaction, safe anywhere) and `tests/tickets_concurrency.ps1` (two real sessions racing for the same customer; it writes tickets, so use a scratch database only).

## Staff and tasks (module 8)

Scripts 25 (schema) and 26 (resources, menu, permissions); functions in `StoredProcedures/Staff/`; `verify/verify_staff.sql` runs with the others. Script 24 stays reserved for the letterhead drop; the next free number is 27.

- **Tables:** `staff_profiles` (optional extra details for a staff user: employee code, designation, alternate mobile, joining date, notes; **no `is_active` of its own**: `users.is_active` is the single switch), `tasks` and `task_status_history` (append-only by trigger, with `assigned_to` so a reassignment shows who it went to). `vw_staff_work` lists a person's tasks and assigned tickets in one shape (reporting and My work read it).
- **Numbers** are `TSK-yyyy-nnnn` from `fn_next_document_no`, taken inside the saving transaction, so a refused task uses none up.
- **Who can be given work:** an active staff-type user whose role has `my_work` view (`fn_role_can_receive_work`, checked by `sp_assert_task_assignee`). An admin-type user, a deactivated user, or a role without My work is refused with NX409 (COLUMN assignedTo). Moving someone with open tasks into a role that cannot see My work is refused too.
- **Status rules** (`sp_check_task_status_move`): assigned to in progress or cancelled; in progress to done or cancelled; done and cancelled are final. Done needs a completion note (22023). `sp_change_task_status` locks the row first. A **staff** caller (`p_visible_to` set) acts only on their own tasks, can start and finish but **cannot cancel** (42501), and cannot create, edit or assign (42501).
- **Deactivation:** `fn_set_user_active` (Foundation) now refuses to deactivate anyone with open tasks or open tickets (`sp_assert_no_open_work`, NX409, COLUMN isActive). Both the Users and the Staff screens go through it.
- **My work** (`fn_get_my_work`): Today = open tasks scheduled today or earlier (overdue ones flagged) plus every open ticket; Upcoming = later or unscheduled tasks; Done = tasks and tickets finished in the last 7 days. Days are business days in the company's time zone. Two reports: `fn_get_my_completed_tasks` and `fn_get_my_resolved_tickets` (by who moved the ticket to resolved).
- **Error codes** as elsewhere: 22023, P0002, NX409, 42501, 23505 (duplicate user name or employee code).
- **Tests:** `tests/test_staff.sql` (188 checks in one rolled-back transaction, safe anywhere) and `tests/staff_concurrency.ps1` (two real sessions: the same status change at the same moment, finish against reassign, and task numbers; it writes tasks, so use a scratch database only).

## Dashboard and reports (module 11)

Scripts 27 (views, indexes, settings) and 28 (resources, menu); functions in `StoredProcedures/Reports/`; `verify/verify_dashboard.sql` runs with the others. The next free script is 29 (24 stays reserved for the letterhead drop). **This module only reads**: no tables, no writes. Every function is `STABLE` (or `IMMUTABLE`), `verify_dashboard.sql` refuses a body that mentions a write statement, and the API reads inside a read-only transaction.

- **Views are row-level** (one row per lead, quotation, order, item, movement or ticket) and carry `tenant_id` and the business-time-zone calendar date: `vw_lead_pipeline`, `vw_quotation_summary`, `vw_order_report`, `vw_inventory_status`, `vw_stock_ledger`, `vw_ticket_summary` (and `vw_business_time_zones`). Functions group over them, so a date range, a week grouping or "my own" numbers need no second view.
- **Money is tax-inclusive as entered**; there is no GST column. **Revenue** is the total of orders *fulfilled* in the period.
- **Settings** (seeded, never overwritten): `ticket_overdue_days` (7), `credit_terms_days` (30), `financial_year_start_month` (4 = April). `fn_get_period_range` turns this month, last month, this quarter and this financial year into a date range and the range to compare it with: a running period is compared with the *same number of elapsed days* of the one before it.
- **Scope.** The company-wide functions take no user. The *own* functions take `p_visible_to` (a staff user's id; NULL = everyone's): leads are "own" when assigned to the user, quotations when made by them *or* on a lead assigned to them. This is stricter than the Quotations list, which also shows a staff user the quotations that have no lead.
- **Dues** (`fn_get_customer_dues`): payments settle the oldest charges first, so the unpaid part of a balance belongs to the newest charges; a customer is overdue `credit_terms_days` after the oldest unpaid charge.
- **Reports** (`fn_report_quotation_conversion`, `fn_report_inventory_movement`, `fn_report_ticket_resolution`) take `p_from` and `p_to` (both missing = the current month; at most 366 days; 22023 naming `from`, `to` or `groupBy`). Unresolved tickets are counted apart and never enter an average; a rate with nothing to divide by is 0.
- **Function files and creation order.** `apply-all.ps1` applies the function files in path order, and a SQL-language function is checked when it is created, so a SQL function may only call functions that sort before it (or be written in PL/pgSQL, which looks them up when it runs). `fn_get_dashboard_open_tickets` is PL/pgSQL for that reason.
- **Tests:** `tests/test_dashboard.sql` (113 checks, one rolled-back transaction; its data is dated 2031 and every function gets an as-of moment, so it is safe on a database with real data: snapshot figures are checked as the *change* the test data makes). `tests/reports_load.sql` seeds 10,000 leads, 10,000 tickets, 50,000 movements and more on a **scratch database only** and fails if any function takes a second (the slowest is under 100 ms).
- **Tickets change in this module:** a staff user can read a ticket that is assigned to them *or raised by them*; only the assignee can change its status (the creator gets 42501). See the Tickets section.

### Demo data for the hand checks (dev only)

`dev/demo_dashboard_seed.sql` writes sample data so the dashboard has something to show: 18 customers, 30 leads (some with follow-ups due, some untouched), 24 quotations (sent ones about to expire), six months of fulfilled orders, overdue customer dues, low-stock items, 11 tickets (unassigned, overdue, raised by the clerk) and 6 tasks scheduled today. Every row is marked DEMO (names start with `DEMO`, document numbers with `DEMO-`, customer mobiles are `70000xxxxx`). It is not a numbered script and is not recorded in `deployment_log`. It creates no user and writes no password: you give it the user names of your test users (`-v sales1= -v sales2= -v clerk=`, optionally `-v tech1= -v tech2=`).
`dev/demo_dashboard_cleanup.sql` removes exactly those rows (switching the append-only triggers off for the length of one transaction and back on before it commits) and keeps any DEMO customer that a row of yours still points at. Both were run on a scratch database: the seed, then every verify script (all pass with the DEMO rows in), then the cleanup, which restored every table's row count to what it was before.
