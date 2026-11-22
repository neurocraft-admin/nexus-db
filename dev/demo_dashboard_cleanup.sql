-- DEV ONLY. Removes exactly the rows dev/demo_dashboard_seed.sql created, and nothing else: the rows marked DEMO (names starting "DEMO", document
-- numbers starting "DEMO-"). Safe to run twice. Not a numbered script and not recorded in deployment_log.
--
--   docker exec -i nexus-pg psql -U postgres -d nexus -v ON_ERROR_STOP=1 < dev/demo_dashboard_cleanup.sql
--
-- Why it switches triggers off for a moment: the history and ledger tables (ticket and task status history, quotation and order status log, lead
-- activities, stock movements) are append-only, and the database refuses to delete from them. The seed wrote DEMO rows there so every screen and every
-- verify script sees a consistent picture; this script removes those rows (inside one transaction) and switches the triggers on again before it commits.
-- Rows YOU made while testing (a ticket, a quotation, a payment on a DEMO customer) are not DEMO rows and are never deleted: a DEMO customer or item
-- that something of yours still points at is kept, and the script says so at the end.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL client_min_messages = warning;
ALTER TABLE ticket_status_history DISABLE TRIGGER trg_ticket_status_history_no_change;
ALTER TABLE task_status_history DISABLE TRIGGER trg_task_status_history_no_change;
ALTER TABLE quotation_status_log DISABLE TRIGGER trg_quotation_status_log_no_change;
ALTER TABLE order_status_log DISABLE TRIGGER trg_order_status_log_no_change;
ALTER TABLE lead_activities DISABLE TRIGGER trg_lead_activities_no_change;
ALTER TABLE stock_movements DISABLE TRIGGER trg_stock_movements_no_change;

DELETE FROM task_status_history h USING tasks t WHERE h.task_id = t.task_id AND t.task_no LIKE 'DEMO-%';
DELETE FROM tasks WHERE task_no LIKE 'DEMO-%';
DELETE FROM ticket_status_history h USING tickets t WHERE h.ticket_id = t.ticket_id AND t.ticket_no LIKE 'DEMO-%';
DELETE FROM ticket_attachments a USING tickets t WHERE a.ticket_id = t.ticket_id AND t.ticket_no LIKE 'DEMO-%';
DELETE FROM tickets WHERE ticket_no LIKE 'DEMO-%';
DELETE FROM order_status_log l USING orders o WHERE l.order_id = o.order_id AND o.order_no LIKE 'DEMO-%';
DELETE FROM order_lines l USING orders o WHERE l.order_id = o.order_id AND o.order_no LIKE 'DEMO-%';
DELETE FROM orders WHERE order_no LIKE 'DEMO-%';
DELETE FROM quotation_status_log l USING quotations q WHERE l.quotation_id = q.quotation_id AND q.quotation_no LIKE 'DEMO-%';
DELETE FROM quotation_lines l USING quotations q WHERE l.quotation_id = q.quotation_id AND q.quotation_no LIKE 'DEMO-%';
DELETE FROM quotations WHERE quotation_no LIKE 'DEMO-%';
DELETE FROM lead_activities a USING leads l WHERE a.lead_id = l.lead_id AND l.lead_no LIKE 'DEMO-%';
DELETE FROM leads WHERE lead_no LIKE 'DEMO-%';
DELETE FROM customer_credit_ledgers g USING customers c WHERE g.customer_id = c.customer_id AND c.customer_name LIKE 'DEMO %' AND g.note LIKE 'DEMO %';
DELETE FROM stock_movements m USING items i WHERE m.item_id = i.item_id AND i.item_code LIKE 'DEMO-%' AND m.note = 'DEMO seed';

-- A DEMO customer or item is removed only when nothing else still refers to it.
DELETE FROM customers c WHERE c.customer_name LIKE 'DEMO %'
   AND NOT EXISTS (SELECT 1 FROM tickets x WHERE x.customer_id = c.customer_id) AND NOT EXISTS (SELECT 1 FROM quotations x WHERE x.customer_id = c.customer_id)
   AND NOT EXISTS (SELECT 1 FROM orders x WHERE x.customer_id = c.customer_id) AND NOT EXISTS (SELECT 1 FROM tasks x WHERE x.customer_id = c.customer_id)
   AND NOT EXISTS (SELECT 1 FROM customer_credit_ledgers x WHERE x.customer_id = c.customer_id);
DELETE FROM items i WHERE i.item_code LIKE 'DEMO-%'
   AND NOT EXISTS (SELECT 1 FROM stock_movements x WHERE x.item_id = i.item_id) AND NOT EXISTS (SELECT 1 FROM quotation_lines x WHERE x.item_id = i.item_id)
   AND NOT EXISTS (SELECT 1 FROM order_lines x WHERE x.item_id = i.item_id);

ALTER TABLE ticket_status_history ENABLE TRIGGER trg_ticket_status_history_no_change;
ALTER TABLE task_status_history ENABLE TRIGGER trg_task_status_history_no_change;
ALTER TABLE quotation_status_log ENABLE TRIGGER trg_quotation_status_log_no_change;
ALTER TABLE order_status_log ENABLE TRIGGER trg_order_status_log_no_change;
ALTER TABLE lead_activities ENABLE TRIGGER trg_lead_activities_no_change;
ALTER TABLE stock_movements ENABLE TRIGGER trg_stock_movements_no_change;
COMMIT;

SELECT 'customers still marked DEMO' AS what, count(*) AS rows FROM customers WHERE customer_name LIKE 'DEMO %'
UNION ALL SELECT 'leads', count(*) FROM leads WHERE lead_no LIKE 'DEMO-%'
UNION ALL SELECT 'quotations', count(*) FROM quotations WHERE quotation_no LIKE 'DEMO-%'
UNION ALL SELECT 'orders', count(*) FROM orders WHERE order_no LIKE 'DEMO-%'
UNION ALL SELECT 'tickets', count(*) FROM tickets WHERE ticket_no LIKE 'DEMO-%'
UNION ALL SELECT 'tasks', count(*) FROM tasks WHERE task_no LIKE 'DEMO-%'
UNION ALL SELECT 'items', count(*) FROM items WHERE item_code LIKE 'DEMO-%';
