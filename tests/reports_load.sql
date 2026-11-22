-- Module 11 (Dashboard and reports): the performance check. Seeds a LARGE data set and times every dashboard and report function: each must answer in
-- under one second on 10,000 leads, 10,000 tickets (and their customers), 50,000 stock movements, 3,000 quotations with their orders, ledger rows for
-- 3,000 customers and 2,000 tasks.
--
-- THIS WRITES MANY ROWS AND DOES NOT CLEAN THEM UP (the history tables are append-only). Run it on a SCRATCH database only, never on nexus-pg:
--   docker exec -i nexus-pg-test psql -U postgres -d <scratch db> -v ON_ERROR_STOP=1 -v scratch=yes < tests/reports_load.sql
-- Without -v scratch=yes, or in a database called nexus, it stops before writing anything. The data does not satisfy verify_tickets.sql (it has no
-- history rows), so do not run that verify script on this database afterwards.
\if :{?scratch}
\else
    \echo 'Refusing to run: add -v scratch=yes and use a scratch database (nexus-pg-test only).'
    \quit
\endif
\set ON_ERROR_STOP on
SET client_min_messages = warning;
DO $$
BEGIN
    IF current_database() IN ('nexus', 'postgres') THEN
        RAISE EXCEPTION 'Refusing to load test data into the database %', current_database();
    END IF;
END;
$$;

DO $$
DECLARE
    c_leads CONSTANT integer := 10000;
    c_tickets CONSTANT integer := 10000;
    c_movements CONSTANT integer := 50000;
    c_items CONSTANT integer := 200;
    c_quotes CONSTANT integer := 3000;
    c_tasks CONSTANT integer := 2000;
    v_admin integer;
    v_unit varchar;
    v_staff_role integer;
BEGIN
    SELECT r.role_id INTO v_staff_role FROM roles r WHERE r.tenant_id = 1 AND r.role_name = 'Staff';
    INSERT INTO users (tenant_id, user_name, full_name, password_hash, role_id, user_type)
    SELECT 1, 'load_user_' || g, 'Load User ' || g, 'x', v_staff_role, 'staff' FROM generate_series(1, 20) g ON CONFLICT DO NOTHING;
    SELECT u.user_id INTO v_admin FROM users u WHERE u.tenant_id = 1 AND u.user_name = 'load_user_1';
    SELECT unit_code INTO v_unit FROM units WHERE tenant_id = 1 ORDER BY unit_code LIMIT 1;

    INSERT INTO customers (tenant_id, customer_name, mobile, address, credit_balance)
    SELECT 1, 'Load Customer ' || g, '8' || lpad(g::text, 9, '0'), 'Address ' || g, 0 FROM generate_series(1, c_tickets + 3000) g ON CONFLICT DO NOTHING;

    INSERT INTO leads (tenant_id, lead_no, lead_name, mobile, lead_source_id, lead_status_id, assigned_to, next_follow_up_date, created_by, is_closed, closed_at, created_at)
    SELECT 1, 'LDLOAD-' || g, 'Load Lead ' || g, '9' || lpad(g::text, 9, '0'),
           (SELECT lead_source_id FROM lead_sources WHERE tenant_id = 1 ORDER BY lead_source_id OFFSET (g % 3) LIMIT 1),
           s.lead_status_id, CASE WHEN g % 4 = 0 THEN NULL ELSE (SELECT user_id FROM users WHERE user_name = 'load_user_' || (1 + g % 20)) END,
           CASE WHEN g % 5 = 0 AND NOT (s.is_won OR s.is_lost) THEN (current_date + (g % 10) - 5) END, v_admin, (s.is_won OR s.is_lost),
           CASE WHEN s.is_won OR s.is_lost THEN now() - make_interval(days => g % 200) END, now() - make_interval(days => g % 400, hours => g % 24)
      FROM generate_series(1, c_leads) g
      JOIN LATERAL (SELECT st.lead_status_id, st.is_won, st.is_lost FROM lead_statuses st WHERE st.tenant_id = 1 ORDER BY st.sort_order OFFSET (g % 6) LIMIT 1) s ON true
    ON CONFLICT DO NOTHING;

    INSERT INTO tickets (tenant_id, ticket_no, customer_id, issue_type_id, description, status, source, assigned_to, resolved_at, closed_at, created_by, created_at)
    SELECT 1, 'TKLOAD-' || t.g, c.customer_id, (SELECT issue_type_id FROM issue_types WHERE tenant_id = 1 ORDER BY issue_type_id OFFSET (t.g % 5) LIMIT 1), 'Load ticket ' || t.g,
           t.st, 'portal', CASE WHEN t.g % 3 = 0 THEN NULL ELSE (SELECT user_id FROM users WHERE user_name = 'load_user_' || (1 + t.g % 20)) END,
           CASE WHEN t.st = 'resolved' THEN now() - make_interval(days => t.g % 300) + make_interval(hours => 1 + t.g % 120) END,
           CASE WHEN t.st = 'closed' THEN now() - make_interval(days => t.g % 300) + make_interval(hours => 1 + t.g % 120) END, NULL,
           now() - make_interval(days => t.g % 300)
      FROM (SELECT n AS g, CASE n % 10 WHEN 0 THEN 'open' WHEN 1 THEN 'open' WHEN 2 THEN 'in_progress' WHEN 3 THEN 'closed' WHEN 4 THEN 'closed' ELSE 'resolved' END AS st
              FROM generate_series(1, c_tickets) n) t
      JOIN customers c ON c.mobile = '8' || lpad(t.g::text, 9, '0') AND c.tenant_id = 1
    ON CONFLICT DO NOTHING;

    INSERT INTO items (tenant_id, item_code, item_name, unit, reorder_level, current_stock)
    SELECT 1, 'LOAD' || lpad(g::text, 4, '0'), 'Load item ' || g, v_unit, CASE WHEN g % 4 = 0 THEN 100 ELSE 0 END, (g * 7) % 150 FROM generate_series(1, c_items) g ON CONFLICT DO NOTHING;
    INSERT INTO stock_movements (tenant_id, item_id, movement_type, quantity, signed_quantity, reference_type, note, created_by, created_at)
    SELECT 1, (SELECT item_id FROM items WHERE tenant_id = 1 AND item_code = 'LOAD' || lpad((1 + g % c_items)::text, 4, '0')),
           t, 1 + g % 9, CASE t WHEN 'out' THEN -(1 + g % 9) ELSE 1 + g % 9 END,
           CASE t WHEN 'in' THEN 'purchase' WHEN 'out' THEN 'order' ELSE 'adjustment' END, CASE WHEN t = 'adjust' THEN 'Load count' END, v_admin,
           now() - make_interval(days => g % 400, mins => g % 1440)
      FROM (SELECT g, CASE WHEN g % 20 = 0 THEN 'adjust' WHEN g % 3 = 0 THEN 'out' ELSE 'in' END AS t FROM generate_series(1, c_movements) g) m;

    INSERT INTO quotations (tenant_id, quotation_no, customer_id, status, quotation_date, valid_until, subtotal, total_amount, created_by, sent_at, created_at)
    SELECT 1, 'QLOAD-' || q.g, c.customer_id, q.s, (now() - make_interval(days => q.g % 350))::date, (now() - make_interval(days => q.g % 350) + interval '30 days')::date,
           50000 + q.g, 50000 + q.g, v_admin, CASE WHEN q.s <> 'draft' THEN now() - make_interval(days => q.g % 350) END, now() - make_interval(days => q.g % 350)
      FROM (SELECT n AS g, CASE n % 6 WHEN 0 THEN 'draft' WHEN 1 THEN 'sent' WHEN 2 THEN 'approved' WHEN 3 THEN 'rejected' WHEN 4 THEN 'expired' ELSE 'converted' END AS s
              FROM generate_series(1, c_quotes) n) q
      JOIN customers c ON c.mobile = '8' || lpad((c_tickets + q.g)::text, 9, '0') AND c.tenant_id = 1;
    INSERT INTO quotation_status_log (tenant_id, quotation_id, from_status, to_status, changed_by, changed_at)
    SELECT 1, q.quotation_id, 'sent', 'approved', v_admin, q.created_at + interval '2 days' FROM quotations q
     WHERE q.tenant_id = 1 AND q.quotation_no LIKE 'QLOAD-%' AND q.status IN ('approved', 'converted');
    INSERT INTO orders (tenant_id, order_no, quotation_id, customer_id, status, payment_mode, total_amount, fulfilled_at, created_by, created_at)
    SELECT 1, 'OLOAD-' || q.quotation_id, q.quotation_id, q.customer_id, 'fulfilled', 'paid', q.total_amount, q.created_at + interval '5 days', v_admin, q.created_at + interval '3 days'
      FROM quotations q WHERE q.tenant_id = 1 AND q.quotation_no LIKE 'QLOAD-%' AND q.status = 'converted';

    INSERT INTO customer_credit_ledgers (tenant_id, customer_id, entry_type, amount, created_by, created_at)
    SELECT 1, c.customer_id, CASE WHEN n = 3 THEN 'payment' ELSE 'charge' END, CASE WHEN n = 3 THEN 5000 ELSE 10000 END, v_admin, now() - make_interval(days => ((c.customer_id % 120) + n * 10)::integer)
      FROM customers c CROSS JOIN generate_series(1, 3) n WHERE c.tenant_id = 1 AND c.customer_id % 4 = 0 AND c.mobile LIKE '8%';
    UPDATE customers SET credit_balance = 15000 WHERE tenant_id = 1 AND customer_id % 4 = 0 AND mobile LIKE '8%';

    INSERT INTO tasks (tenant_id, task_no, task_type, title, assigned_to, scheduled_at, status, completion_note, completed_at, created_by)
    SELECT 1, 'TSLOAD-' || g, 'service', 'Load task ' || g, (SELECT user_id FROM users WHERE user_name = 'load_user_' || (1 + g % 20)), now() + make_interval(days => (g % 20) - 10), s,
           CASE WHEN s = 'done' THEN 'Done' END, CASE WHEN s IN ('done', 'cancelled') THEN now() END, v_admin
      FROM (SELECT g, CASE g % 5 WHEN 0 THEN 'done' WHEN 1 THEN 'cancelled' WHEN 2 THEN 'in_progress' ELSE 'assigned' END AS s FROM generate_series(1, c_tasks) g) t;
END;
$$;
ANALYZE;

SELECT 'leads' AS what, count(*) AS rows FROM leads WHERE tenant_id = 1 UNION ALL SELECT 'tickets', count(*) FROM tickets WHERE tenant_id = 1
UNION ALL SELECT 'stock movements', count(*) FROM stock_movements WHERE tenant_id = 1 UNION ALL SELECT 'quotations', count(*) FROM quotations WHERE tenant_id = 1
UNION ALL SELECT 'orders', count(*) FROM orders WHERE tenant_id = 1 UNION ALL SELECT 'ledger rows', count(*) FROM customer_credit_ledgers WHERE tenant_id = 1
UNION ALL SELECT 'tasks', count(*) FROM tasks WHERE tenant_id = 1;

-- Time every function. Each must finish in under one second (the reports use the widest range, 366 days). A slow one fails the script.
CREATE TEMP TABLE t_timing (function_name text, milliseconds numeric);
DO $$
DECLARE
    c_limit_ms CONSTANT numeric := 1000;
    v_p record;
    v_user integer;
    v_start timestamptz;
    v_ms numeric;
    v_names text[] := ARRAY[
        'fn_get_dashboard_summary', 'fn_get_revenue_by_month', 'fn_get_lead_pipeline', 'fn_get_leads_by_source', 'fn_get_recent_quotations',
        'fn_get_dashboard_low_stock', 'fn_get_dashboard_open_tickets', 'fn_get_overdue_payments', 'fn_get_technician_workload', 'fn_get_operations_summary',
        'fn_get_needs_assignment', 'fn_get_schedule_today', 'fn_get_sales_summary', 'fn_get_leads_to_contact', 'fn_get_follow_ups_due',
        'fn_get_expiring_quotations', 'fn_get_my_ticket_summary', 'fn_get_my_tickets', 'fn_find_customer', 'fn_report_quotation_conversion',
        'fn_report_inventory_movement', 'fn_report_ticket_resolution'];
    v_name text;
BEGIN
    SELECT r.period_from, r.period_to, r.prev_from, r.prev_to INTO v_p FROM fn_get_period_range(1, 'this_month') r;
    SELECT u.user_id INTO v_user FROM users u WHERE u.user_name = 'load_user_3';
    FOREACH v_name IN ARRAY v_names LOOP
        v_start := clock_timestamp();
        CASE v_name
            WHEN 'fn_get_dashboard_summary' THEN PERFORM count(*) FROM fn_get_dashboard_summary(1, v_p.period_from, v_p.period_to, v_p.prev_from, v_p.prev_to);
            WHEN 'fn_get_revenue_by_month' THEN PERFORM count(*) FROM fn_get_revenue_by_month(1, 6);
            WHEN 'fn_get_lead_pipeline' THEN PERFORM count(*) FROM fn_get_lead_pipeline(1, v_p.period_from, v_p.period_to, NULL);
            WHEN 'fn_get_leads_by_source' THEN PERFORM count(*) FROM fn_get_leads_by_source(1, v_p.period_from, v_p.period_to, NULL);
            WHEN 'fn_get_recent_quotations' THEN PERFORM count(*) FROM fn_get_recent_quotations(1, NULL, 5);
            WHEN 'fn_get_dashboard_low_stock' THEN PERFORM count(*) FROM fn_get_dashboard_low_stock(1, 5);
            WHEN 'fn_get_dashboard_open_tickets' THEN PERFORM count(*) FROM fn_get_dashboard_open_tickets(1, 4);
            WHEN 'fn_get_overdue_payments' THEN PERFORM count(*) FROM fn_get_overdue_payments(1, 4);
            WHEN 'fn_get_technician_workload' THEN PERFORM count(*) FROM fn_get_technician_workload(1);
            WHEN 'fn_get_operations_summary' THEN PERFORM count(*) FROM fn_get_operations_summary(1);
            WHEN 'fn_get_needs_assignment' THEN PERFORM count(*) FROM fn_get_needs_assignment(1, 5);
            WHEN 'fn_get_schedule_today' THEN PERFORM count(*) FROM fn_get_schedule_today(1);
            WHEN 'fn_get_sales_summary' THEN PERFORM count(*) FROM fn_get_sales_summary(1, v_user, v_p.period_from, v_p.period_to, v_p.prev_from, v_p.prev_to);
            WHEN 'fn_get_leads_to_contact' THEN PERFORM count(*) FROM fn_get_leads_to_contact(1, v_user, 4);
            WHEN 'fn_get_follow_ups_due' THEN PERFORM count(*) FROM fn_get_follow_ups_due(1, v_user, 5);
            WHEN 'fn_get_expiring_quotations' THEN PERFORM count(*) FROM fn_get_expiring_quotations(1, v_user, 3);
            WHEN 'fn_get_my_ticket_summary' THEN PERFORM count(*) FROM fn_get_my_ticket_summary(1, v_user);
            WHEN 'fn_get_my_tickets' THEN PERFORM count(*) FROM fn_get_my_tickets(1, v_user, 5);
            WHEN 'fn_find_customer' THEN PERFORM count(*) FROM fn_find_customer(1, 'Load Customer 1', NULL, 5);
            WHEN 'fn_report_quotation_conversion' THEN PERFORM count(*) FROM fn_report_quotation_conversion(1, current_date - 365, current_date, 'week');
            WHEN 'fn_report_inventory_movement' THEN PERFORM count(*) FROM fn_report_inventory_movement(1, current_date - 365, current_date, NULL);
            ELSE PERFORM count(*) FROM fn_report_ticket_resolution(1, current_date - 365, current_date, NULL);
        END CASE;
        v_ms := round(extract(epoch FROM clock_timestamp() - v_start) * 1000, 1);
        INSERT INTO t_timing VALUES (v_name, v_ms);
        IF v_ms > c_limit_ms THEN
            RAISE EXCEPTION 'TOO SLOW: % took % ms (the limit is % ms)', v_name, v_ms, c_limit_ms;
        END IF;
    END LOOP;
END;
$$;
SELECT function_name, milliseconds FROM t_timing ORDER BY milliseconds DESC;
SELECT count(*) || ' functions timed, all under one second; slowest ' || max(milliseconds) || ' ms' AS result FROM t_timing;
