-- Module 11 (Dashboard and reports): behaviour tests for the database, one rolled-back transaction, safe on any database that has scripts
-- 00-28 and the function files applied (an empty one or one with real data).
--   docker exec -i nexus-pg-test psql -U postgres -d <db> -v ON_ERROR_STOP=1 < tests/test_dashboard.sql
-- The test data is dated in 2031 and "now" is 15 November 2031 (an as-of moment is passed to every function), so no real row can fall in a
-- period the test measures. Figures that are SNAPSHOTS of the whole company (open tickets, dues, quotes awaiting reply, low stock) include
-- whatever real data exists, so they are checked as the CHANGE the test data makes. Hand calculation of every number is in the comments.
\set ON_ERROR_STOP on
SET client_min_messages = warning;
BEGIN;

CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v bigint);
CREATE TEMP TABLE t_pass (label text);
CREATE FUNCTION pg_temp.ctx(p_key text) RETURNS bigint LANGUAGE sql AS $$ SELECT v FROM t_ctx WHERE k = p_key $$;
CREATE FUNCTION pg_temp.setctx(p_key text, p_val bigint) RETURNS void LANGUAGE sql AS
    $$ INSERT INTO t_ctx VALUES (p_key, p_val) ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v $$;
CREATE FUNCTION pg_temp.ok(p_label text, p_cond boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN
        RAISE EXCEPTION 'FAILED: %', p_label;
    END IF;
    INSERT INTO t_pass VALUES (p_label);
END;
$$;
CREATE FUNCTION pg_temp.fails(p_label text, p_sql text, p_state text, p_column text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_state text; v_column text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
        GET STACKED DIAGNOSTICS v_column = COLUMN_NAME;
    END;
    PERFORM pg_temp.ok(p_label || ' [refused with ' || p_state || ', got ' || COALESCE(v_state, 'no error') || ']', v_state = p_state);
    IF p_column IS NOT NULL THEN
        PERFORM pg_temp.ok(p_label || ' [names column ' || p_column || ']', v_column = p_column);
    END IF;
END;
$$;
CREATE FUNCTION pg_temp.ts(p_text text) RETURNS timestamptz LANGUAGE sql AS $$ SELECT p_text::timestamptz $$;
CREATE FUNCTION pg_temp.asof() RETURNS timestamptz LANGUAGE sql AS $$ SELECT '2031-11-15 06:30:00+00'::timestamptz $$;   -- 12:00 in India

-- Known settings for the test (rolled back with everything else).
UPDATE app_settings SET setting_value = 'Asia/Kolkata' WHERE tenant_id = 1 AND setting_key = 'business_time_zone';
UPDATE app_settings SET setting_value = '30' WHERE tenant_id = 1 AND setting_key = 'credit_terms_days';
UPDATE app_settings SET setting_value = '7' WHERE tenant_id = 1 AND setting_key = 'ticket_overdue_days';
UPDATE app_settings SET setting_value = '4' WHERE tenant_id = 1 AND setting_key = 'financial_year_start_month';

-- ---------------------------------------------------------------- the period ranges
DO $$
DECLARE
    r record;
BEGIN
    r := (SELECT x FROM fn_get_period_range(1, 'this_month', DATE '2031-11-15') x);
    PERFORM pg_temp.ok('this month: 1 to 30 November, compared with the same 14 elapsed days of October (1 to 15)',
        r.period_from = DATE '2031-11-01' AND r.period_to = DATE '2031-11-30' AND r.prev_from = DATE '2031-10-01' AND r.prev_to = DATE '2031-10-15'
        AND r.period_label = 'This month' AND r.prev_label = 'October');
    r := (SELECT x FROM fn_get_period_range(1, 'last_month', DATE '2031-11-15') x);
    PERFORM pg_temp.ok('last month: all of October, compared with ALL of September (a finished period is not cut short)',
        r.period_from = DATE '2031-10-01' AND r.period_to = DATE '2031-10-31' AND r.prev_from = DATE '2031-09-01' AND r.prev_to = DATE '2031-09-30'
        AND r.period_label = 'October 2031' AND r.prev_label = 'September');
    r := (SELECT x FROM fn_get_period_range(1, 'this_quarter', DATE '2031-11-15') x);
    PERFORM pg_temp.ok('this quarter (April-start financial year): October to December, against the same 45 days of July to September',
        r.period_from = DATE '2031-10-01' AND r.period_to = DATE '2031-12-31' AND r.prev_from = DATE '2031-07-01' AND r.prev_to = DATE '2031-08-15');
    r := (SELECT x FROM fn_get_period_range(1, 'this_financial_year', DATE '2031-11-15') x);
    PERFORM pg_temp.ok('this financial year: 1 April 2031 to 31 March 2032, against the same 228 days of the one before',
        r.period_from = DATE '2031-04-01' AND r.period_to = DATE '2032-03-31' AND r.prev_from = DATE '2030-04-01' AND r.prev_to = DATE '2030-11-15');
    r := (SELECT x FROM fn_get_period_range(1, 'this_financial_year', DATE '2031-02-10') x);
    PERFORM pg_temp.ok('in February the financial year began the previous April', r.period_from = DATE '2030-04-01' AND r.period_to = DATE '2031-03-31');
    UPDATE app_settings SET setting_value = '1' WHERE tenant_id = 1 AND setting_key = 'financial_year_start_month';
    r := (SELECT x FROM fn_get_period_range(1, 'this_quarter', DATE '2031-11-15') x);
    PERFORM pg_temp.ok('with January as the financial year start, quarters are calendar quarters', r.period_from = DATE '2031-10-01');
    r := (SELECT x FROM fn_get_period_range(1, 'this_financial_year', DATE '2031-11-15') x);
    PERFORM pg_temp.ok('... and the year is the calendar year', r.period_from = DATE '2031-01-01' AND r.period_to = DATE '2031-12-31');
    UPDATE app_settings SET setting_value = '4' WHERE tenant_id = 1 AND setting_key = 'financial_year_start_month';
    PERFORM pg_temp.fails('an unknown period', $q$SELECT period_from FROM fn_get_period_range(1, 'this_week', DATE '2031-11-15')$q$, '22023', 'period');
    r := (SELECT x FROM fn_get_period_range(1, 'this_month') x);
    PERFORM pg_temp.ok('with no date given the period starts today in the business time zone', r.period_from = date_trunc('month', fn_business_today(1))::date);
END;
$$;

-- ---------------------------------------------------------------- baselines: what the company already had before the test data
CREATE TEMP TABLE t_sum0 AS SELECT x.new_leads, x.new_leads_prev, x.leads_won, x.leads_won_prev, x.revenue, x.revenue_prev, x.open_leads, x.open_leads_first,
       x.open_leads_last, x.dues_total, x.dues_overdue_customers, x.open_tickets, x.overdue_tickets, x.awaiting_reply_count, x.awaiting_reply_value,
       x.low_stock_count, x.low_stock_below_half
  FROM fn_get_dashboard_summary(1, DATE '2031-11-01', DATE '2031-11-30', DATE '2031-10-01', DATE '2031-10-15', pg_temp.asof()) x;
CREATE TEMP TABLE t_ops0 AS SELECT x.needs_assignment, x.needs_assignment_over_day, x.open_tickets, x.overdue_tickets, x.tasks_today, x.overdue_tasks,
       x.technicians_idle, x.low_stock_count, x.low_stock_below_half FROM fn_get_operations_summary(1, pg_temp.asof()) x;
CREATE TEMP TABLE t_low0 AS SELECT COALESCE(max(total_count), 0) AS n FROM fn_get_dashboard_low_stock(1, 1);
CREATE TEMP TABLE t_dues0 AS SELECT count(*) AS overdue FROM fn_get_overdue_payments(1, 100000, pg_temp.asof());

-- ---------------------------------------------------------------- the data
CREATE FUNCTION pg_temp.new_user(p_name text, p_full text, p_role text, p_type text DEFAULT 'staff') RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO users (tenant_id, user_name, full_name, password_hash, role_id, user_type, is_active)
    SELECT 1, p_name, p_full, 'x', r.role_id, p_type, true FROM roles r WHERE r.tenant_id = 1 AND r.role_name = p_role RETURNING user_id
$$;
CREATE FUNCTION pg_temp.cust(p_name text, p_mobile text, p_balance numeric DEFAULT 0) RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO customers (tenant_id, customer_name, mobile, address, credit_balance) VALUES (1, p_name, p_mobile, 'Address of ' || p_name, p_balance) RETURNING customer_id
$$;
CREATE FUNCTION pg_temp.lead(p_no text, p_mobile text, p_source text, p_status text, p_assigned text, p_created text, p_follow date DEFAULT NULL,
                             p_closed text DEFAULT NULL, p_active boolean DEFAULT true) RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO leads (tenant_id, lead_no, lead_name, mobile, lead_source_id, lead_status_id, assigned_to, next_follow_up_date, created_by,
                       is_active, is_closed, closed_at, created_at)
    SELECT 1, p_no, 'Lead ' || p_no, p_mobile, pg_temp.ctx(p_source)::integer, st.lead_status_id,
           CASE WHEN p_assigned IS NULL THEN NULL ELSE pg_temp.ctx(p_assigned)::integer END, p_follow, pg_temp.ctx('admin')::integer, p_active,
           p_closed IS NOT NULL, p_closed::timestamptz, p_created::timestamptz
      FROM lead_statuses st WHERE st.tenant_id = 1 AND st.status_name = p_status
    RETURNING lead_id
$$;
CREATE FUNCTION pg_temp.quote(p_no text, p_by text, p_customer text, p_lead text, p_status text, p_created text, p_sent text, p_total numeric, p_valid date,
                              p_approved text DEFAULT NULL, p_label text DEFAULT NULL) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    v_id bigint;
BEGIN
    INSERT INTO quotations (tenant_id, quotation_no, customer_id, lead_id, status, quotation_date, valid_until, subtotal, total_amount, created_by, sent_at, created_at)
    VALUES (1, p_no, CASE WHEN p_customer IS NULL THEN NULL ELSE pg_temp.ctx(p_customer) END, CASE WHEN p_lead IS NULL THEN NULL ELSE pg_temp.ctx(p_lead) END,
            p_status, p_created::date, p_valid, p_total, p_total, pg_temp.ctx(p_by)::integer, p_sent::timestamptz, p_created::timestamptz)
    RETURNING quotation_id INTO v_id;
    IF p_approved IS NOT NULL THEN
        INSERT INTO quotation_status_log (tenant_id, quotation_id, from_status, to_status, changed_by, changed_at) VALUES (1, v_id, 'sent', 'approved', pg_temp.ctx(p_by)::integer, p_approved::timestamptz);
    END IF;
    IF p_label IS NOT NULL THEN
        INSERT INTO quotation_lines (tenant_id, quotation_id, line_type, description, unit, quantity, unit_price, line_total, sort_order)
        VALUES (1, v_id, 'custom', p_label, 'nos', 1, p_total, p_total, 1);
    END IF;
    RETURN v_id;
END;
$$;
CREATE FUNCTION pg_temp.ticket(p_no text, p_customer text, p_type text, p_status text, p_created text, p_by text, p_assigned text, p_resolved text DEFAULT NULL,
                               p_closed text DEFAULT NULL) RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO tickets (tenant_id, ticket_no, customer_id, issue_type_id, other_issue_text, description, status, source, assigned_to, resolved_at, closed_at, created_by, created_at)
    VALUES (1, p_no, pg_temp.ctx(p_customer), CASE WHEN p_type IS NULL THEN NULL ELSE pg_temp.ctx(p_type)::integer END, CASE WHEN p_type IS NULL THEN 'Strange noise' END,
            'Problem ' || p_no, p_status, CASE WHEN p_by IS NULL THEN 'portal' ELSE 'internal' END, CASE WHEN p_assigned IS NULL THEN NULL ELSE pg_temp.ctx(p_assigned)::integer END,
            p_resolved::timestamptz, p_closed::timestamptz, CASE WHEN p_by IS NULL THEN NULL ELSE pg_temp.ctx(p_by)::integer END, p_created::timestamptz)
    RETURNING ticket_id
$$;
CREATE FUNCTION pg_temp.task(p_no text, p_to text, p_status text, p_at text, p_customer text DEFAULT NULL, p_address text DEFAULT NULL) RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO tasks (tenant_id, task_no, task_type, title, customer_id, assigned_to, scheduled_at, visit_address, status, completion_note, completed_at, created_by)
    VALUES (1, p_no, 'service', 'Job ' || p_no, CASE WHEN p_customer IS NULL THEN NULL ELSE pg_temp.ctx(p_customer) END, pg_temp.ctx(p_to)::integer, p_at::timestamptz, p_address, p_status,
            CASE WHEN p_status = 'done' THEN 'Finished' END, CASE WHEN p_status IN ('done', 'cancelled') THEN p_at::timestamptz END, pg_temp.ctx('admin')::integer)
    RETURNING task_id
$$;
CREATE FUNCTION pg_temp.item(p_code text, p_reorder numeric, p_stock numeric, p_active boolean DEFAULT true) RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO items (tenant_id, item_code, item_name, unit, reorder_level, current_stock, is_active)
    VALUES (1, p_code, 'Item ' || p_code, (SELECT unit_code FROM units WHERE tenant_id = 1 ORDER BY unit_code LIMIT 1), p_reorder, p_stock, p_active) RETURNING item_id
$$;
CREATE FUNCTION pg_temp.move(p_item text, p_type text, p_qty numeric, p_at text) RETURNS void LANGUAGE sql AS $$
    INSERT INTO stock_movements (tenant_id, item_id, movement_type, quantity, signed_quantity, reference_type, note, created_by, created_at)
    VALUES (1, pg_temp.ctx(p_item), CASE WHEN p_type = 'adj-' OR p_type = 'adj+' THEN 'adjust' ELSE p_type END, p_qty,
            CASE WHEN p_type = 'out' OR p_type = 'adj-' THEN -p_qty ELSE p_qty END,
            CASE WHEN p_type IN ('adj-', 'adj+') THEN 'adjustment' WHEN p_type = 'in' THEN 'purchase' ELSE 'order' END,
            CASE WHEN p_type IN ('adj-', 'adj+') THEN 'Stock count' END, pg_temp.ctx('admin')::integer, p_at::timestamptz)
$$;
CREATE FUNCTION pg_temp.charge(p_customer text, p_type text, p_amount numeric, p_at text) RETURNS void LANGUAGE sql AS $$
    INSERT INTO customer_credit_ledgers (tenant_id, customer_id, entry_type, amount, created_by, created_at)
    VALUES (1, pg_temp.ctx(p_customer), p_type, p_amount, pg_temp.ctx('admin')::integer, p_at::timestamptz)
$$;


DO $$
DECLARE
    v_id bigint;
BEGIN
    INSERT INTO roles (tenant_id, role_name) VALUES (1, 'db_frontdesk');
    PERFORM pg_temp.setctx('admin', pg_temp.new_user('db_admin', 'Deepu Admin', 'Admin', 'admin'));
    PERFORM pg_temp.setctx('s1', pg_temp.new_user('db_s1', 'Ravi Technician', 'Staff'));
    PERFORM pg_temp.setctx('s2', pg_temp.new_user('db_s2', 'Suma Technician', 'Staff'));
    PERFORM pg_temp.setctx('s3', pg_temp.new_user('db_s3', 'Arun Idle', 'Staff'));
    PERFORM pg_temp.setctx('clerk', pg_temp.new_user('db_clerk', 'Meena Clerk', 'db_frontdesk'));
    INSERT INTO lead_sources (tenant_id, source_name) VALUES (1, 'DB Src A') RETURNING lead_source_id INTO v_id;
    PERFORM pg_temp.setctx('srcA', v_id);
    INSERT INTO lead_sources (tenant_id, source_name) VALUES (1, 'DB Src B') RETURNING lead_source_id INTO v_id;
    PERFORM pg_temp.setctx('srcB', v_id);
    PERFORM pg_temp.setctx('itA', (SELECT issue_type_id FROM issue_types WHERE tenant_id = 1 AND issue_type_name = 'Not working'));
    PERFORM pg_temp.setctx('itB', (SELECT issue_type_id FROM issue_types WHERE tenant_id = 1 AND issue_type_name = 'Inverter fault'));
    PERFORM pg_temp.setctx('c1', pg_temp.cust('Anil Kumar', '9871300001'));
    PERFORM pg_temp.setctx('c2', pg_temp.cust('Bindu Nair', '9871300002'));
    PERFORM pg_temp.setctx('c3', pg_temp.cust('Chitra Devi', '9871300003'));
    PERFORM pg_temp.setctx('c4', pg_temp.cust('Dinesh Pillai', '9871300004'));
    PERFORM pg_temp.setctx('c5', pg_temp.cust('Elsy Thomas', '9871300005'));
    PERFORM pg_temp.setctx('c6', pg_temp.cust('Femi Joseph', '9871300006'));
    PERFORM pg_temp.setctx('d1', pg_temp.cust('Dues One', '9871300011', 60000));
    PERFORM pg_temp.setctx('d2', pg_temp.cust('Dues Two', '9871300012', 0));
    PERFORM pg_temp.setctx('d3', pg_temp.cust('Dues Three', '9871300013', 25000));
    PERFORM pg_temp.setctx('d4', pg_temp.cust('Dues Four', '9871300014', 10000));
    PERFORM pg_temp.setctx('d5', pg_temp.cust('Dues Five', '9871300015', -5000));
    -- Credit: d1 owes 60000 (50000 from 1 Sep and 30000 from 1 Oct, 20000 paid: the payment settles the OLDEST charge first, so 1 Sep is still unpaid).
    PERFORM pg_temp.charge('d1', 'charge', 50000, '2031-09-01 05:00+00');
    PERFORM pg_temp.charge('d1', 'charge', 30000, '2031-10-01 05:00+00');
    PERFORM pg_temp.charge('d1', 'payment', 20000, '2031-10-05 05:00+00');
    PERFORM pg_temp.charge('d2', 'charge', 40000, '2031-10-20 05:00+00');
    PERFORM pg_temp.charge('d2', 'payment', 40000, '2031-10-25 05:00+00');
    PERFORM pg_temp.charge('d3', 'charge', 25000, '2031-11-01 05:00+00');
    -- d4: 10000 charged 1 Aug and paid 15 Aug, then 10000 charged 10 Oct: the unpaid charge is the 10 Oct one.
    PERFORM pg_temp.charge('d4', 'charge', 10000, '2031-08-01 05:00+00');
    PERFORM pg_temp.charge('d4', 'payment', 10000, '2031-08-15 05:00+00');
    PERFORM pg_temp.charge('d4', 'charge', 10000, '2031-10-10 05:00+00');
    PERFORM pg_temp.charge('d5', 'payment', 5000, '2031-11-02 05:00+00');
    -- Leads (statuses are the seeded New, Contacted, Qualified, Negotiation, Won, Lost). November: L1-L5 open, L6 won on 10 Nov, LX inactive.
    PERFORM pg_temp.setctx('L1', pg_temp.lead('DBL1', '9701000001', 'srcA', 'New', 's1', '2031-11-03 05:00+00', DATE '2031-11-14'));
    PERFORM pg_temp.setctx('L2', pg_temp.lead('DBL2', '9701000002', 'srcA', 'New', 's1', '2031-11-05 05:00+00', DATE '2031-11-15'));
    PERFORM pg_temp.setctx('L3', pg_temp.lead('DBL3', '9701000003', 'srcA', 'New', 's2', '2031-11-07 05:00+00', DATE '2031-11-10'));
    PERFORM pg_temp.setctx('L4', pg_temp.lead('DBL4', '9701000004', 'srcB', 'Contacted', 's1', '2031-11-09 05:00+00', DATE '2031-11-20'));
    PERFORM pg_temp.setctx('L5', pg_temp.lead('DBL5', '9701000005', 'srcB', 'Qualified', 's2', '2031-11-11 05:00+00'));
    PERFORM pg_temp.setctx('L6', pg_temp.lead('DBL6', '9701000006', 'srcB', 'Won', 's1', '2031-11-01 05:00+00', NULL, '2031-11-10 05:00+00'));
    PERFORM pg_temp.lead('DBLX', '9701000007', 'srcA', 'New', 's1', '2031-11-12 05:00+00', NULL, NULL, false);
    -- October: Oa, Ob, Od, Oe open; Oc won on 12 Oct. September: Z1 lost on 8 Nov.
    PERFORM pg_temp.lead('DBOA', '9701000011', 'srcA', 'New', 's1', '2031-10-03 05:00+00');
    PERFORM pg_temp.lead('DBOB', '9701000012', 'srcA', 'Contacted', 's2', '2031-10-05 05:00+00');
    PERFORM pg_temp.lead('DBOC', '9701000013', 'srcA', 'Won', 's1', '2031-10-09 05:00+00', NULL, '2031-10-12 05:00+00');
    PERFORM pg_temp.lead('DBOD', '9701000014', 'srcA', 'New', NULL, '2031-10-14 05:00+00');
    PERFORM pg_temp.lead('DBOE', '9701000015', 'srcA', 'Qualified', 's1', '2031-10-20 05:00+00');
    PERFORM pg_temp.lead('DBZ1', '9701000021', 'srcA', 'Lost', 's2', '2031-09-20 05:00+00', NULL, '2031-11-08 05:00+00');
    -- Quotations: made by s1, s2 or the admin; Q4, Q10 are the admin's on s1's lead L1; Q11 is on s2's lead L3.
    PERFORM pg_temp.quote('DBQ1', 's1', 'c1', NULL, 'sent', '2031-11-02 05:00+00', '2031-11-03 05:00+00', 100000, DATE '2031-11-17', NULL, '5 kW on-grid');
    PERFORM pg_temp.quote('DBQ2', 's1', 'c1', NULL, 'approved', '2031-11-04 05:00+00', '2031-11-05 05:00+00', 200000, DATE '2031-12-04', '2031-11-06 05:00+00');
    PERFORM pg_temp.setctx('Q3', pg_temp.quote('DBQ3', 's2', 'c2', NULL, 'converted', '2031-11-06 05:00+00', '2031-11-07 05:00+00', 300000, DATE '2031-12-06', '2031-11-08 05:00+00'));
    PERFORM pg_temp.quote('DBQ4', 'admin', NULL, 'L1', 'rejected', '2031-11-08 05:00+00', '2031-11-09 05:00+00', 50000, DATE '2031-11-30');
    PERFORM pg_temp.quote('DBQ5', 's2', 'c2', NULL, 'draft', '2031-11-09 05:00+00', NULL, 70000, DATE '2031-11-30');
    PERFORM pg_temp.quote('DBQ6', 's2', 'c3', NULL, 'expired', '2031-11-10 05:00+00', '2031-11-10 05:00+00', 40000, DATE '2031-11-12');
    PERFORM pg_temp.quote('DBQ7', 's1', 'c3', NULL, 'sent', '2031-11-11 05:00+00', '2031-11-11 05:00+00', 80000, DATE '2031-11-25');
    PERFORM pg_temp.quote('DBQ10', 'admin', NULL, 'L1', 'sent', '2031-11-12 05:00+00', '2031-11-12 05:00+00', 30000, DATE '2031-11-30');
    PERFORM pg_temp.setctx('Q2', (SELECT quotation_id FROM quotations WHERE tenant_id = 1 AND quotation_no = 'DBQ2'));
    PERFORM pg_temp.setctx('Q8', pg_temp.quote('DBQ8', 's1', 'c1', NULL, 'converted', '2031-10-20 05:00+00', '2031-10-21 05:00+00', 150000, DATE '2031-11-20', '2031-10-22 05:00+00'));
    PERFORM pg_temp.quote('DBQ9', 's2', 'c3', NULL, 'sent', '2031-10-25 05:00+00', '2031-10-25 05:00+00', 90000, DATE '2031-11-24');
    PERFORM pg_temp.quote('DBQ11', 'admin', 'c4', 'L3', 'draft', '2031-09-15 05:00+00', NULL, 10000, DATE '2031-10-15');
    INSERT INTO orders (tenant_id, order_no, quotation_id, customer_id, status, payment_mode, total_amount, fulfilled_at, created_by, created_at)
    VALUES (1, 'DBO1', pg_temp.ctx('Q3'), pg_temp.ctx('c2'), 'fulfilled', 'paid', 300000, '2031-11-12 05:00+00', pg_temp.ctx('admin'), '2031-11-08 05:00+00'),
           (1, 'DBO2', pg_temp.ctx('Q2'), pg_temp.ctx('c1'), 'new', NULL, 200000, NULL, pg_temp.ctx('admin'), '2031-11-07 05:00+00'),
           (1, 'DBO3', pg_temp.ctx('Q8'), pg_temp.ctx('c1'), 'fulfilled', 'credit', 150000, '2031-10-28 05:00+00', pg_temp.ctx('admin'), '2031-10-24 05:00+00');
    -- Tickets: T1 is old and unassigned (portal), T2 is in progress with s1 (raised by the clerk), T3 is the clerk's newest, T4 and T6 are resolved (20 and
    -- 72 hours), T5 was closed without work.
    PERFORM pg_temp.ticket('DBT1', 'c2', 'itA', 'open', '2031-11-05 06:00+00', NULL, NULL);
    PERFORM pg_temp.ticket('DBT2', 'c1', 'itA', 'in_progress', '2031-11-10 05:00+00', 'clerk', 's1');
    PERFORM pg_temp.ticket('DBT3', 'c3', NULL, 'open', '2031-11-15 00:30+00', 'clerk', NULL);
    PERFORM pg_temp.ticket('DBT4', 'c4', 'itA', 'resolved', '2031-11-13 00:00+00', 'clerk', 's2', '2031-11-13 20:00+00');
    PERFORM pg_temp.ticket('DBT5', 'c5', 'itA', 'closed', '2031-11-12 05:00+00', 'clerk', NULL, NULL, '2031-11-13 05:00+00');
    PERFORM pg_temp.ticket('DBT6', 'c6', 'itB', 'resolved', '2031-11-01 00:00+00', NULL, 's1', '2031-11-04 00:00+00');
    -- Tasks on 15 Nov (India): K1 09:00 and K2 11:30 open, K3 yesterday and still open (overdue), K4 tomorrow, K5 done at 07:30, K6 cancelled.
    PERFORM pg_temp.task('DBK1', 's1', 'assigned', '2031-11-15 03:30+00', 'c1', 'Plot 4, Temple Road');
    PERFORM pg_temp.task('DBK2', 's2', 'in_progress', '2031-11-15 06:00+00', 'c2');
    PERFORM pg_temp.task('DBK3', 's1', 'assigned', '2031-11-14 05:00+00', 'c3');
    PERFORM pg_temp.task('DBK4', 's2', 'assigned', '2031-11-16 05:00+00', 'c1');
    PERFORM pg_temp.task('DBK5', 's1', 'done', '2031-11-15 02:00+00', 'c2');
    PERFORM pg_temp.task('DBK6', 's2', 'cancelled', '2031-11-15 04:00+00', 'c3');
    -- Stock: I1 and I2 are low (I1 below half), I3 is fine, I4 is inactive, I5 has no alert.
    PERFORM pg_temp.setctx('I1', pg_temp.item('DBI1', 20, 8));
    PERFORM pg_temp.setctx('I2', pg_temp.item('DBI2', 4, 2));
    PERFORM pg_temp.setctx('I3', pg_temp.item('DBI3', 100, 500));
    PERFORM pg_temp.setctx('I4', pg_temp.item('DBI4', 10, 1, false));
    PERFORM pg_temp.setctx('I5', pg_temp.item('DBI5', 0, 0));
    PERFORM pg_temp.move('I1', 'in', 30, '2031-10-20 05:00+00');
    PERFORM pg_temp.move('I1', 'in', 10, '2031-11-03 05:00+00');
    PERFORM pg_temp.move('I1', 'out', 30, '2031-11-05 05:00+00');
    PERFORM pg_temp.move('I1', 'adj-', 2, '2031-11-10 05:00+00');
    PERFORM pg_temp.move('I2', 'in', 5, '2031-11-02 05:00+00');
    PERFORM pg_temp.move('I2', 'out', 3, '2031-11-12 05:00+00');
    PERFORM pg_temp.move('I3', 'in', 500, '2031-10-01 05:00+00');
    PERFORM pg_temp.move('I4', 'in', 1, '2031-10-01 05:00+00');
END;
$$;

-- ---------------------------------------------------------------- the headline numbers (company-wide)
DO $$
DECLARE
    a record; b record;
BEGIN
    a := (SELECT x FROM fn_get_dashboard_summary(1, DATE '2031-11-01', DATE '2031-11-30', DATE '2031-10-01', DATE '2031-10-15', pg_temp.asof()) x);
    b := (SELECT x FROM t_sum0 x);
    PERFORM pg_temp.ok('new leads in November: L1 to L6 (the inactive one is not counted) = 6; the same days of October (1 to 15) = 4',
        a.new_leads - b.new_leads = 6 AND a.new_leads_prev - b.new_leads_prev = 4);
    PERFORM pg_temp.ok('leads won: 1 in November (L6), 1 in the compared days (closed 12 Oct)', a.leads_won - b.leads_won = 1 AND a.leads_won_prev - b.leads_won_prev = 1);
    PERFORM pg_temp.ok('lead conversion = won / new: 1 of 6 = 16.7 %, and 1 of 4 = 25.0 % before', a.lead_conversion = 16.7 AND a.lead_conversion_prev = 25.0);
    PERFORM pg_temp.ok('revenue = the fulfilled order total: 300000 in November, none in 1 to 15 October (the October order was fulfilled on the 28th)',
        a.revenue - b.revenue = 300000 AND a.revenue_prev - b.revenue_prev = 0);
    PERFORM pg_temp.ok('open pipeline: 9 more open leads (5 in November, 4 in October), 5 more in the first open stage',
        a.open_leads - b.open_leads = 9 AND a.open_leads_first - b.open_leads_first = 5 AND a.open_leads_last - b.open_leads_last = 0);
    PERFORM pg_temp.ok('the stage names come from the pipeline order, not from words in the code',
        a.open_leads_first_name = (SELECT st.status_name FROM lead_statuses st WHERE st.tenant_id = 1 AND st.is_active AND NOT st.is_won AND NOT st.is_lost ORDER BY st.sort_order LIMIT 1)
        AND a.open_leads_last_name = (SELECT st.status_name FROM lead_statuses st WHERE st.tenant_id = 1 AND st.is_active AND NOT st.is_won AND NOT st.is_lost ORDER BY st.sort_order DESC LIMIT 1));
    PERFORM pg_temp.ok('dues: 60000 + 25000 + 10000 = 95000 owed, 2 customers overdue (d1 and d4; d3 is not yet due)',
        a.dues_total - b.dues_total = 95000 AND a.dues_overdue_customers - b.dues_overdue_customers = 2);
    PERFORM pg_temp.ok('open tickets +3 (T1, T2, T3), overdue +1 (T1 is 10 days old; T2 is 5)', a.open_tickets - b.open_tickets = 3 AND a.overdue_tickets - b.overdue_tickets = 1);
    PERFORM pg_temp.ok('quotes awaiting reply: 4 sent (Q1, Q7, Q10, Q9) worth 100000 + 80000 + 30000 + 90000 = 300000',
        a.awaiting_reply_count - b.awaiting_reply_count = 4 AND a.awaiting_reply_value - b.awaiting_reply_value = 300000);
    PERFORM pg_temp.ok('low stock: +2 (I1 and I2), of which +1 is below half the minimum (I1; the inactive and the no-alert items do not count)',
        a.low_stock_count - b.low_stock_count = 2 AND a.low_stock_below_half - b.low_stock_below_half = 1);
    a := (SELECT x FROM fn_get_dashboard_summary(1, DATE '2032-05-01', DATE '2032-05-31', DATE '2032-04-01', DATE '2032-04-15', pg_temp.asof()) x);
    PERFORM pg_temp.ok('a period with no leads has conversion 0, not a division by zero', a.new_leads = 0 AND a.lead_conversion = 0 AND a.lead_conversion_prev = 0 AND a.revenue = 0);
END;
$$;

DO $$
BEGIN
    PERFORM pg_temp.ok('revenue by month: six months, oldest first, October 150000, November 300000, the rest 0',
        (SELECT string_agg(to_char(r.month_start, 'YYYY-MM') || ':' || r.revenue::bigint, ',' ORDER BY r.month_start)
           FROM fn_get_revenue_by_month(1, 6, DATE '2031-11-15') r) = '2031-06:0,2031-07:0,2031-08:0,2031-09:0,2031-10:150000,2031-11:300000');
    PERFORM pg_temp.ok('... and the order count goes with it', (SELECT sum(r.orders_fulfilled) FROM fn_get_revenue_by_month(1, 6, DATE '2031-11-15') r) = 2);
    PERFORM pg_temp.ok('a cancelled or new order is never revenue (the November order that is still "new" adds nothing)',
        (SELECT r.revenue FROM fn_get_revenue_by_month(1, 1, DATE '2031-11-15') r) = 300000);
END;
$$;

-- ---------------------------------------------------------------- the pipeline and sources, company-wide and own
DO $$
BEGIN
    PERFORM pg_temp.ok('s1''s pipeline: New 3, Contacted 1, Qualified 1, Negotiation 0, Won 1 (this month), Lost 0 (the open stages are today''s, Won and Lost are the month''s)',
        (SELECT string_agg(p.lead_count::text, ',' ORDER BY p.sort_order) FROM fn_get_lead_pipeline(1, DATE '2031-11-01', DATE '2031-11-30', pg_temp.ctx('s1')::integer) p) = '3,1,1,0,1,0');
    PERFORM pg_temp.ok('s2''s pipeline: New 1, Contacted 1, Qualified 1, Negotiation 0, Won 0, Lost 1 (the lead lost on 8 Nov counts in November)',
        (SELECT string_agg(p.lead_count::text, ',' ORDER BY p.sort_order) FROM fn_get_lead_pipeline(1, DATE '2031-11-01', DATE '2031-11-30', pg_temp.ctx('s2')::integer) p) = '1,1,1,0,0,1');
    PERFORM pg_temp.ok('every active status is listed even when it is empty', (SELECT count(*) FROM fn_get_lead_pipeline(1, DATE '2031-11-01', DATE '2031-11-30', pg_temp.ctx('s3')::integer)) =
        (SELECT count(*) FROM lead_statuses WHERE tenant_id = 1 AND is_active));
    PERFORM pg_temp.ok('a user with no leads sees all zeros', (SELECT sum(p.lead_count) FROM fn_get_lead_pipeline(1, DATE '2031-11-01', DATE '2031-11-30', pg_temp.ctx('s3')::integer) p) = 0);
    PERFORM pg_temp.ok('leads by source, company-wide: A 3 (L1, L2, L3), B 3 (L4, L5, L6)',
        (SELECT string_agg(s.source_name || ':' || s.lead_count, ',' ORDER BY s.source_name) FROM fn_get_leads_by_source(1, DATE '2031-11-01', DATE '2031-11-30', NULL) s
          WHERE s.source_name LIKE 'DB Src%') = 'DB Src A:3,DB Src B:3');
    PERFORM pg_temp.ok('leads by source, s1''s own: A 2, B 2 (L4 and L6)',
        (SELECT string_agg(s.source_name || ':' || s.lead_count, ',' ORDER BY s.source_name) FROM fn_get_leads_by_source(1, DATE '2031-11-01', DATE '2031-11-30', pg_temp.ctx('s1')::integer) s) = 'DB Src A:2,DB Src B:2');
    PERFORM pg_temp.ok('the New leads of s1, oldest first: DBOA (43 days), DBL1 (12), DBL2 (10); nobody else''s, none that is closed',
        (SELECT string_agg(c.lead_no || ':' || c.age_days, ',' ORDER BY c.rn) FROM (SELECT f.lead_no, f.age_days, row_number() OVER () AS rn
           FROM fn_get_leads_to_contact(1, pg_temp.ctx('s1')::integer, 10, pg_temp.asof()) f) c) = 'DBOA:43,DBL1:12,DBL2:10');
    PERFORM pg_temp.ok('... a limit of 1 gives the oldest only', (SELECT f.lead_no FROM fn_get_leads_to_contact(1, pg_temp.ctx('s1')::integer, 1, pg_temp.asof()) f) = 'DBOA');
    PERFORM pg_temp.ok('s2''s: DBOB is Contacted so only DBL3', (SELECT string_agg(f.lead_no, ',') FROM fn_get_leads_to_contact(1, pg_temp.ctx('s2')::integer, 10, pg_temp.asof()) f) = 'DBL3');
    PERFORM pg_temp.ok('follow-ups due for s1: DBL1 (yesterday, 1 day overdue) then DBL2 (today); not DBL4 (the 20th), not the won lead',
        (SELECT string_agg(f.lead_no || ':' || f.days_overdue, ',' ORDER BY f.rn) FROM (SELECT g.lead_no, g.days_overdue, row_number() OVER () AS rn
           FROM fn_get_follow_ups_due(1, pg_temp.ctx('s1')::integer, 10, pg_temp.asof()) g) f) = 'DBL1:1,DBL2:0');
    PERFORM pg_temp.ok('... with the total on every row, and s2 sees only theirs (DBL3, 5 days)',
        (SELECT max(f.total_count) FROM fn_get_follow_ups_due(1, pg_temp.ctx('s1')::integer, 1, pg_temp.asof()) f) = 2
        AND (SELECT string_agg(f.lead_no || ':' || f.days_overdue, ',') FROM fn_get_follow_ups_due(1, pg_temp.ctx('s2')::integer, 10, pg_temp.asof()) f) = 'DBL3:5');
END;
$$;

-- ---------------------------------------------------------------- the Sales view's numbers, own scope
DO $$
DECLARE
    a record;
BEGIN
    a := (SELECT x FROM fn_get_sales_summary(1, pg_temp.ctx('s1')::integer, DATE '2031-11-01', DATE '2031-11-30', DATE '2031-10-01', DATE '2031-10-15') x);
    PERFORM pg_temp.ok('s1: new leads 4 (L1, L2, L4, L6) against 2 (the Oct 1-15 ones: DBOA and DBOC)', a.new_leads = 4 AND a.new_leads_prev = 2);
    PERFORM pg_temp.ok('s1: open leads 5 (L1, L2, L4, DBOA, DBOE) of which 3 not contacted yet (the New ones: L1, L2, DBOA)', a.open_leads = 5 AND a.not_contacted = 3);
    PERFORM pg_temp.ok('s1: awaiting reply 3 worth 210000: Q1 and Q7 (made by s1) and Q10 (the admin''s, on s1''s lead)', a.awaiting_reply_count = 3 AND a.awaiting_reply_value = 210000);
    PERFORM pg_temp.ok('s1: won 1, 200000 approved (Q2 on 6 Nov), conversion 1 of 4 = 25.0 against 1 of 2 = 50.0', a.won = 1 AND a.won_value = 200000 AND a.conversion = 25.0 AND a.conversion_prev = 50.0);
    a := (SELECT x FROM fn_get_sales_summary(1, pg_temp.ctx('s2')::integer, DATE '2031-11-01', DATE '2031-11-30', DATE '2031-10-01', DATE '2031-10-15') x);
    PERFORM pg_temp.ok('s2: new 2 (L3, L5) against 1 (DBOB); open 3, 1 not contacted; awaiting 1 worth 90000 (Q9); won 0 so conversion 0.0, but 300000 approved (Q3)',
        a.new_leads = 2 AND a.new_leads_prev = 1 AND a.open_leads = 3 AND a.not_contacted = 1 AND a.awaiting_reply_count = 1 AND a.awaiting_reply_value = 90000
        AND a.won = 0 AND a.conversion = 0.0 AND a.won_value = 300000);
    a := (SELECT x FROM fn_get_sales_summary(1, pg_temp.ctx('s3')::integer, DATE '2031-11-01', DATE '2031-11-30', DATE '2031-10-01', DATE '2031-10-15') x);
    PERFORM pg_temp.ok('a user with nothing sees zeros, no error, no division by zero',
        a.new_leads = 0 AND a.open_leads = 0 AND a.not_contacted = 0 AND a.awaiting_reply_count = 0 AND a.awaiting_reply_value = 0 AND a.won = 0 AND a.won_value = 0 AND a.conversion = 0);
    PERFORM pg_temp.ok('s1''s recent quotations: the admin''s two on s1''s lead are included, newest first (Q10, Q7, Q4)',
        (SELECT string_agg(q.quotation_no, ',' ORDER BY q.rn) FROM (SELECT f.quotation_no, row_number() OVER () AS rn
           FROM fn_get_recent_quotations(1, pg_temp.ctx('s1')::integer, 3) f) q) = 'DBQ10,DBQ7,DBQ4');
    PERFORM pg_temp.ok('... six in all for s1, and a quotation with a line shows its description',
        (SELECT count(*) FROM fn_get_recent_quotations(1, pg_temp.ctx('s1')::integer, 20)) = 6
        AND (SELECT f.package_label FROM fn_get_recent_quotations(1, pg_temp.ctx('s1')::integer, 20) f WHERE f.quotation_no = 'DBQ1') = '5 kW on-grid');
    PERFORM pg_temp.ok('s2''s own: Q6, Q5, Q3, Q9 and Q11 (on s2''s lead L3) and none of s1''s',
        (SELECT string_agg(q.quotation_no, ',' ORDER BY q.rn) FROM (SELECT f.quotation_no, row_number() OVER () AS rn
           FROM fn_get_recent_quotations(1, pg_temp.ctx('s2')::integer, 20) f) q) = 'DBQ6,DBQ5,DBQ3,DBQ9,DBQ11');
    PERFORM pg_temp.ok('a quotation has the right status, total and party',
        (SELECT f.status = 'sent' AND f.total_amount = 30000 AND f.party_name = 'Lead DBL1' FROM fn_get_recent_quotations(1, pg_temp.ctx('s1')::integer, 1) f));
    PERFORM pg_temp.ok('expiring soon for s1: only Q1 (valid until the 17th, 2 days left); Q7 is the 25th, Q10 the 30th',
        (SELECT string_agg(e.quotation_no || ':' || e.days_left, ',') FROM fn_get_expiring_quotations(1, pg_temp.ctx('s1')::integer, 10, pg_temp.asof()) e) = 'DBQ1:2');
    PERFORM pg_temp.ok('... with the customer''s mobile for the Call button',
        (SELECT e.party_mobile FROM fn_get_expiring_quotations(1, pg_temp.ctx('s1')::integer, 10, pg_temp.asof()) e) = '9871300001');
    PERFORM pg_temp.ok('... s2 has none within 7 days (Q9 is valid until the 24th), and company-wide it is the same single one',
        NOT EXISTS (SELECT 1 FROM fn_get_expiring_quotations(1, pg_temp.ctx('s2')::integer, 10, pg_temp.asof()))
        AND (SELECT string_agg(e.quotation_no, ',') FROM fn_get_expiring_quotations(1, NULL, 10, pg_temp.asof()) e) = 'DBQ1');
END;
$$;

-- ---------------------------------------------------------------- operations: tickets, tasks, people, stock
DO $$
DECLARE
    a record; b record;
BEGIN
    PERFORM pg_temp.ok('the oldest open tickets, oldest first: T1 (10 days, overdue), T2 (5), T3 (0)',
        (SELECT string_agg(f.ticket_no || ':' || f.age_days || ':' || f.is_overdue, ',' ORDER BY f.rn) FROM (SELECT g.ticket_no, g.age_days, g.is_overdue, row_number() OVER () AS rn
           FROM fn_get_dashboard_open_tickets(1, 100000, pg_temp.asof()) g WHERE g.ticket_no LIKE 'DBT%') f) = 'DBT1:10:true,DBT2:5:false,DBT3:0:false');
    PERFORM pg_temp.ok('closed and resolved tickets are not in it', NOT EXISTS (SELECT 1 FROM fn_get_dashboard_open_tickets(1, 100000, pg_temp.asof()) g WHERE g.ticket_no IN ('DBT4', 'DBT5', 'DBT6')));
    PERFORM pg_temp.ok('needs assignment: T1 then T3 (T2 has someone); nothing that is resolved',
        (SELECT string_agg(f.ticket_no || ':' || f.age_days, ',' ORDER BY f.rn) FROM (SELECT g.ticket_no, g.age_days, row_number() OVER () AS rn
           FROM fn_get_needs_assignment(1, 100000, pg_temp.asof()) g WHERE g.ticket_no LIKE 'DBT%') f) = 'DBT1:10,DBT3:0');
    PERFORM pg_temp.ok('technician workload: s1 has 2 tasks for today (K1 and the overdue K3, 1 overdue) and 1 ticket (T2) = 3 items; s2 has 1 task (K2; K4 is tomorrow, K6 cancelled) = 1; s3 0',
        (SELECT string_agg(w.full_name || ':' || w.tasks_today || ':' || w.overdue_tasks || ':' || w.open_tickets || ':' || w.items, ',' ORDER BY w.rn)
           FROM (SELECT g.full_name, g.tasks_today, g.overdue_tasks, g.open_tickets, g.items, row_number() OVER () AS rn
                   FROM fn_get_technician_workload(1, pg_temp.asof()) g WHERE g.user_id IN (pg_temp.ctx('s1'), pg_temp.ctx('s2'), pg_temp.ctx('s3'))) w)
        = 'Ravi Technician:2:1:1:3,Suma Technician:1:0:0:1,Arun Idle:0:0:0:0');
    PERFORM pg_temp.ok('a user whose role cannot be given work, and the admin, are not technicians',
        NOT EXISTS (SELECT 1 FROM fn_get_technician_workload(1, pg_temp.asof()) g WHERE g.user_id IN (pg_temp.ctx('clerk'), pg_temp.ctx('admin'))));
    a := (SELECT x FROM fn_get_operations_summary(1, pg_temp.asof()) x);
    b := (SELECT x FROM t_ops0 x);
    PERFORM pg_temp.ok('operations: +2 need assignment (+1 waiting over a day: T1), +3 open tickets (+1 overdue)',
        a.needs_assignment - b.needs_assignment = 2 AND a.needs_assignment_over_day - b.needs_assignment_over_day = 1
        AND a.open_tickets - b.open_tickets = 3 AND a.overdue_tickets - b.overdue_tickets = 1);
    PERFORM pg_temp.ok('operations: +3 tasks for today (K1, K2, K3), +1 overdue, +1 person with nothing on (s3), +2 low-stock items (+1 below half)',
        a.tasks_today - b.tasks_today = 3 AND a.overdue_tasks - b.overdue_tasks = 1 AND a.technicians_idle - b.technicians_idle = 1
        AND a.low_stock_count - b.low_stock_count = 2 AND a.low_stock_below_half - b.low_stock_below_half = 1);
    PERFORM pg_temp.ok('today''s schedule in time order: yesterday''s overdue K3, the done K5 (07:30), K1 (09:00), K2 (11:30); not tomorrow''s K4 or the cancelled K6',
        (SELECT string_agg(f.task_no, ',' ORDER BY f.rn) FROM (SELECT g.task_no, row_number() OVER () AS rn FROM fn_get_schedule_today(1, pg_temp.asof()) g WHERE g.task_no LIKE 'DBK%') f) = 'DBK3,DBK5,DBK1,DBK2');
    PERFORM pg_temp.ok('only the overdue one is marked, the address is the visit address else the customer''s, the technician is named',
        (SELECT bool_and((g.task_no = 'DBK3') = g.is_overdue) FROM fn_get_schedule_today(1, pg_temp.asof()) g WHERE g.task_no LIKE 'DBK%')
        AND (SELECT g.address FROM fn_get_schedule_today(1, pg_temp.asof()) g WHERE g.task_no = 'DBK1') = 'Plot 4, Temple Road'
        AND (SELECT g.address FROM fn_get_schedule_today(1, pg_temp.asof()) g WHERE g.task_no = 'DBK2') = 'Address of Bindu Nair'
        AND (SELECT g.technician_name FROM fn_get_schedule_today(1, pg_temp.asof()) g WHERE g.task_no = 'DBK2') = 'Suma Technician');
    PERFORM pg_temp.ok('low stock, most short first: I1 (8 of 20, below half) then I2 (2 of 4); not the fine, inactive or no-alert items',
        (SELECT string_agg(f.item_code || ':' || f.is_below_half, ',' ORDER BY f.rn) FROM (SELECT g.item_code, g.is_below_half, row_number() OVER () AS rn
           FROM fn_get_dashboard_low_stock(1, 100000) g WHERE g.item_code LIKE 'DBI%') f) = 'DBI1:true,DBI2:false');
    PERFORM pg_temp.ok('... and the total says how many there are in all (+2)',
        (SELECT max(g.total_count) FROM fn_get_dashboard_low_stock(1, 1) g) - (SELECT n FROM t_low0) = 2);
END;
$$;

-- ---------------------------------------------------------------- the front desk: own tickets, dues, customer lookup
DO $$
DECLARE
    a record;
BEGIN
    a := (SELECT x FROM fn_get_my_ticket_summary(1, pg_temp.ctx('clerk')::integer, pg_temp.asof()) x);
    PERFORM pg_temp.ok('the clerk raised 1 today (T3, still unassigned) and 4 this week (T2, T3, T4, T5), 1 of them resolved (T4)',
        a.raised_today = 1 AND a.raised_today_unassigned = 1 AND a.raised_week = 4 AND a.raised_week_resolved = 1);
    PERFORM pg_temp.ok('open tickets that are the clerk''s (raised by them): T2 and T3, none over 7 days', a.open_mine = 2 AND a.open_mine_overdue = 0);
    a := (SELECT x FROM fn_get_my_ticket_summary(1, pg_temp.ctx('s1')::integer, pg_temp.asof()) x);
    PERFORM pg_temp.ok('a technician''s open tickets are the ones assigned to them (T2), raised none', a.open_mine = 1 AND a.raised_today = 0 AND a.raised_week = 0);
    PERFORM pg_temp.ok('tickets I raised, newest first, any status: T3, T4, T5, T2; the first has nobody yet and T4 shows who has it',
        (SELECT string_agg(f.ticket_no, ',' ORDER BY f.rn) FROM (SELECT g.ticket_no, row_number() OVER () AS rn FROM fn_get_my_tickets(1, pg_temp.ctx('clerk')::integer, 10) g) f) = 'DBT3,DBT4,DBT5,DBT2'
        AND (SELECT g.is_unassigned FROM fn_get_my_tickets(1, pg_temp.ctx('clerk')::integer, 10) g WHERE g.ticket_no = 'DBT3')
        AND (SELECT g.assigned_to_name FROM fn_get_my_tickets(1, pg_temp.ctx('clerk')::integer, 10) g WHERE g.ticket_no = 'DBT4') = 'Suma Technician');
    PERFORM pg_temp.ok('a user who raised none sees none', NOT EXISTS (SELECT 1 FROM fn_get_my_tickets(1, pg_temp.ctx('s3')::integer, 10)));
    PERFORM pg_temp.ok('overdue payments: d1 first (oldest unpaid charge 1 Sep, due 1 Oct, 45 days late), then d4 (the unpaid one is the 10 Oct charge, due 9 Nov, 6 days)',
        (SELECT string_agg(f.customer_name || ':' || f.balance::bigint || ':' || f.days_overdue, ',' ORDER BY f.rn) FROM (SELECT g.customer_name, g.balance, g.days_overdue, row_number() OVER () AS rn
           FROM fn_get_overdue_payments(1, 100000, pg_temp.asof()) g WHERE g.customer_name LIKE 'Dues%') f) = 'Dues One:60000:45,Dues Four:10000:6');
    PERFORM pg_temp.ok('not listed: paid up (d2), not yet due (d3), an advance (d5)',
        NOT EXISTS (SELECT 1 FROM fn_get_overdue_payments(1, 100000, pg_temp.asof()) g WHERE g.customer_name IN ('Dues Two', 'Dues Three', 'Dues Five')));
    PERFORM pg_temp.ok('the whole list of owing customers includes d3 with 0 days late',
        (SELECT d.days_overdue FROM fn_get_customer_dues(1, DATE '2031-11-15') d WHERE d.customer_name = 'Dues Three') = 0
        AND NOT EXISTS (SELECT 1 FROM fn_get_customer_dues(1, DATE '2031-11-15') d WHERE d.customer_name IN ('Dues Two', 'Dues Five')));
    PERFORM pg_temp.ok('two more overdue customers than before the test data', (SELECT count(*) FROM fn_get_overdue_payments(1, 100000, pg_temp.asof())) - (SELECT overdue FROM t_dues0) = 2);
    UPDATE app_settings SET setting_value = '60' WHERE tenant_id = 1 AND setting_key = 'credit_terms_days';
    PERFORM pg_temp.ok('with 60 days of credit terms d1 is 15 days late and d4 is not late',
        (SELECT d.days_overdue FROM fn_get_customer_dues(1, DATE '2031-11-15') d WHERE d.customer_name = 'Dues One') = 15
        AND (SELECT d.days_overdue FROM fn_get_customer_dues(1, DATE '2031-11-15') d WHERE d.customer_name = 'Dues Four') = 0);
    UPDATE app_settings SET setting_value = '30' WHERE tenant_id = 1 AND setting_key = 'credit_terms_days';
    PERFORM pg_temp.ok('find a customer by name: the open ticket (number, status, the technician''s FIRST name) and the latest quotation',
        (SELECT f.customer_name = 'Anil Kumar' AND f.open_ticket_no = 'DBT2' AND f.open_ticket_status = 'in_progress' AND f.open_ticket_technician = 'Ravi'
                AND f.last_quotation_no = 'DBQ2' AND f.last_quotation_status = 'approved' AND f.credit_balance = 0 FROM fn_find_customer(1, 'anil', NULL, 100) f WHERE f.customer_id = pg_temp.ctx('c1')));
    PERFORM pg_temp.ok('... by the digits of the mobile (7 digits) and not by a shorter (2 digits) or a blank search',
        (SELECT string_agg(f.customer_name, ',') FROM fn_find_customer(1, '1300001', NULL, 100) f WHERE f.mobile LIKE '98713%') = 'Anil Kumar'
        AND NOT EXISTS (SELECT 1 FROM fn_find_customer(1, '+98', NULL, 5)) AND NOT EXISTS (SELECT 1 FROM fn_find_customer(1, '   ', NULL, 5))
        AND NOT EXISTS (SELECT 1 FROM fn_find_customer(1, NULL, NULL, 5)));
    PERFORM pg_temp.ok('a customer whose ticket is unassigned has no technician name', (SELECT f.open_ticket_no = 'DBT3' AND f.open_ticket_technician IS NULL FROM fn_find_customer(1, 'chitra', NULL, 100) f WHERE f.customer_id = pg_temp.ctx('c3')));
    PERFORM pg_temp.ok('a customer with no open ticket has none shown (T4 is resolved)', (SELECT f.open_ticket_no IS NULL FROM fn_find_customer(1, 'dinesh', NULL, 100) f WHERE f.customer_id = pg_temp.ctx('c4')));
    PERFORM pg_temp.ok('the latest quotation is the newest one the user may see: Q5 for Bindu (a draft, newer than Q3)', (SELECT f.last_quotation_no FROM fn_find_customer(1, 'bindu', NULL, 100) f WHERE f.customer_id = pg_temp.ctx('c2')) = 'DBQ5');
    PERFORM pg_temp.ok('a quotation on ANOTHER staff user''s lead is hidden from a staff user (s1) but not from its owner (s2) or an administrator',
        (SELECT f.last_quotation_no IS NULL FROM fn_find_customer(1, 'dinesh', pg_temp.ctx('s1')::integer, 100) f WHERE f.customer_id = pg_temp.ctx('c4'))
        AND (SELECT f.last_quotation_no FROM fn_find_customer(1, 'dinesh', pg_temp.ctx('s2')::integer, 100) f WHERE f.customer_id = pg_temp.ctx('c4')) = 'DBQ11'
        AND (SELECT f.last_quotation_no FROM fn_find_customer(1, 'dinesh', NULL, 100) f WHERE f.customer_id = pg_temp.ctx('c4')) = 'DBQ11');
    PERFORM pg_temp.ok('the limit is honoured', (SELECT count(*) FROM fn_find_customer(1, 'e', NULL, 2)) = 2);
END;
$$;

-- ---------------------------------------------------------------- report: quotation conversion
DO $$
DECLARE
    r record;
BEGIN
    r := (SELECT f FROM fn_report_quotation_conversion(1, DATE '2031-11-01', DATE '2031-11-30', 'month') f WHERE f.period_start = DATE '2031-11-01');
    PERFORM pg_temp.ok('November: 8 created, 7 sent, 2 approved, 1 rejected, 1 expired, 1 converted; rate 2 / 7 = 28.6 %',
        r.created = 8 AND r.sent = 7 AND r.approved = 2 AND r.rejected = 1 AND r.expired = 1 AND r.converted = 1 AND r.conversion_rate = 28.6);
    PERFORM pg_temp.ok('November values: 870000 created, 500000 approved (Q2 + Q3), tax-inclusive as entered', r.created_value = 870000 AND r.approved_value = 500000);
    PERFORM pg_temp.ok('November orders: 2 created worth 500000, 1 fulfilled worth 300000', r.orders_created = 2 AND r.orders_created_value = 500000 AND r.orders_fulfilled = 1 AND r.orders_fulfilled_value = 300000);
    r := (SELECT f FROM fn_report_quotation_conversion(1, DATE '2031-10-01', DATE '2031-11-30', 'month') f WHERE f.period_start = DATE '2031-10-01');
    PERFORM pg_temp.ok('October: 2 created, 2 sent, 1 approved and converted, rate 50.0 %, 240000 created, 150000 approved, 1 order created and fulfilled (150000)',
        r.created = 2 AND r.sent = 2 AND r.approved = 1 AND r.converted = 1 AND r.conversion_rate = 50.0 AND r.created_value = 240000 AND r.approved_value = 150000
        AND r.orders_created = 1 AND r.orders_fulfilled = 1 AND r.orders_fulfilled_value = 150000);
    r := (SELECT f FROM fn_report_quotation_conversion(1, DATE '2031-10-01', DATE '2031-11-30', 'month') f WHERE f.is_total);
    PERFORM pg_temp.ok('the total row adds both months: 10 created, 9 sent, 3 approved, rate 33.3 % (from the totals, not an average of rates), 1110000 / 650000',
        r.created = 10 AND r.sent = 9 AND r.approved = 3 AND r.conversion_rate = 33.3 AND r.created_value = 1110000 AND r.approved_value = 650000
        AND r.orders_created = 3 AND r.orders_created_value = 650000 AND r.orders_fulfilled = 2 AND r.orders_fulfilled_value = 450000 AND r.period_start IS NULL);
    PERFORM pg_temp.ok('the periods are in order and the total comes last',
        (SELECT string_agg(coalesce(to_char(f.period_start, 'YYYY-MM-DD'), 'total'), ',' ORDER BY f.rn) FROM (SELECT g.period_start, row_number() OVER () AS rn
           FROM fn_report_quotation_conversion(1, DATE '2031-10-01', DATE '2031-11-30', 'month') g) f) = '2031-10-01,2031-11-01,total');
    PERFORM pg_temp.ok('by week (Mondays): 1 and 2 Nov are in the week of 27 Oct, then 3 Nov has 4 and 10 Nov has 3',
        (SELECT string_agg(coalesce(to_char(f.period_start, 'MM-DD'), 'total') || ':' || f.created, ',' ORDER BY f.rn) FROM (SELECT g.period_start, g.created, row_number() OVER () AS rn
           FROM fn_report_quotation_conversion(1, DATE '2031-11-01', DATE '2031-11-15', 'week') g) f) = '10-27:1,11-03:4,11-10:3,total:8');
    r := (SELECT x FROM fn_report_quotation_conversion(1, DATE '2032-05-01', DATE '2032-05-31', 'month') x);
    PERFORM pg_temp.ok('a range with no quotations is one total row with rate 0 (nothing sent, no division by zero)',
        (SELECT count(*) FROM fn_report_quotation_conversion(1, DATE '2032-05-01', DATE '2032-05-31', 'month')) = 1 AND r.is_total AND r.created = 0 AND r.conversion_rate = 0);
END;
$$;

-- ---------------------------------------------------------------- report: inventory movement
DO $$
BEGIN
    PERFORM pg_temp.ok('November: I1 opened with 30, 10 in, 30 out, -2 adjusted = 8; I2 0 + 5 - 3 = 2; I3 opened with 500, no movement = 500; the inactive I4 still shows its 1',
        (SELECT string_agg(m.item_code || ':' || trim_scale(m.opening) || ':' || trim_scale(m.stock_in) || ':' || trim_scale(m.stock_out) || ':' || trim_scale(m.adjustments) || ':' || trim_scale(m.closing), ',' ORDER BY m.item_code)
           FROM fn_report_inventory_movement(1, DATE '2031-11-01', DATE '2031-11-30', NULL) m WHERE m.item_code LIKE 'DBI%')
        = 'DBI1:30:10:30:-2:8,DBI2:0:5:3:0:2,DBI3:500:0:0:0:500,DBI4:1:0:0:0:1');
    PERFORM pg_temp.ok('opening + in - out + adjustments = closing for every item, and the closing equals the stock on hand (no later movement)',
        (SELECT bool_and(m.closing = m.opening + m.stock_in - m.stock_out + m.adjustments AND m.closing = m.current_stock)
           FROM fn_report_inventory_movement(1, DATE '2031-11-01', DATE '2031-11-30', NULL) m WHERE m.item_code LIKE 'DBI%'));
    PERFORM pg_temp.ok('an item with no movement and no stock is not listed (I5)', NOT EXISTS (SELECT 1 FROM fn_report_inventory_movement(1, DATE '2031-11-01', DATE '2031-11-30', NULL) m WHERE m.item_code = 'DBI5'));
    PERFORM pg_temp.ok('October alone: I1 opens 0 and receives 30, I3 receives 500',
        (SELECT string_agg(m.item_code || ':' || trim_scale(m.opening) || ':' || trim_scale(m.stock_in) || ':' || trim_scale(m.closing), ',' ORDER BY m.item_code)
           FROM fn_report_inventory_movement(1, DATE '2031-10-01', DATE '2031-10-31', NULL) m WHERE m.item_code IN ('DBI1', 'DBI3'))
        = 'DBI1:0:30:30,DBI3:0:500:500');
    PERFORM pg_temp.ok('one item only', (SELECT string_agg(m.item_code, ',') FROM fn_report_inventory_movement(1, DATE '2031-11-01', DATE '2031-11-30', pg_temp.ctx('I1')) m) = 'DBI1');
END;
$$;

-- ---------------------------------------------------------------- report: ticket resolution
DO $$
BEGIN
    PERFORM pg_temp.ok('November by issue type: "Not working" has 4 tickets, 1 resolved in 20 hours (so average and maximum 20.0), 3 unresolved, 100 % within 48 hours',
        (SELECT r.tickets = 4 AND r.resolved = 1 AND r.unresolved = 3 AND r.avg_hours = 20.0 AND r.max_hours = 20.0 AND r.within_48h = 1 AND r.within_48h_share = 100.0
           FROM fn_report_ticket_resolution(1, DATE '2031-11-01', DATE '2031-11-30', NULL) r WHERE r.issue_type_id = pg_temp.ctx('itA')));
    PERFORM pg_temp.ok('"Inverter fault": 1 ticket resolved in 72 hours, 0 % within 48 hours',
        (SELECT r.tickets = 1 AND r.resolved = 1 AND r.avg_hours = 72.0 AND r.max_hours = 72.0 AND r.within_48h = 0 AND r.within_48h_share = 0
           FROM fn_report_ticket_resolution(1, DATE '2031-11-01', DATE '2031-11-30', NULL) r WHERE r.issue_type_id = pg_temp.ctx('itB')));
    PERFORM pg_temp.ok('free-text issues are one "Other" row: 1 ticket, unresolved, no average (NULL, not 0)',
        (SELECT r.issue_text = 'Other' AND r.tickets = 1 AND r.resolved = 0 AND r.unresolved = 1 AND r.avg_hours IS NULL AND r.within_48h_share = 0
           FROM fn_report_ticket_resolution(1, DATE '2031-11-01', DATE '2031-11-30', NULL) r WHERE r.issue_type_id IS NULL AND NOT r.is_total));
    PERFORM pg_temp.ok('the total: 6 tickets, 2 resolved, 4 unresolved (the unresolved are counted apart and never in the average), average (20 + 72) / 2 = 46.0, maximum 72.0, 1 of 2 within 48 hours = 50.0 %',
        (SELECT r.tickets = 6 AND r.resolved = 2 AND r.unresolved = 4 AND r.avg_hours = 46.0 AND r.max_hours = 72.0 AND r.within_48h = 1 AND r.within_48h_share = 50.0
           FROM fn_report_ticket_resolution(1, DATE '2031-11-01', DATE '2031-11-30', NULL) r WHERE r.is_total));
    PERFORM pg_temp.ok('a ticket closed without work is unresolved: it is in the 4, not in any average',
        (SELECT r.unresolved FROM fn_report_ticket_resolution(1, DATE '2031-11-01', DATE '2031-11-30', NULL) r WHERE r.is_total) = 4);
    PERFORM pg_temp.ok('one issue type only: its row and a total for it',
        (SELECT count(*) = 2 AND max(r.tickets) FILTER (WHERE r.is_total) = 4 FROM fn_report_ticket_resolution(1, DATE '2031-11-01', DATE '2031-11-30', pg_temp.ctx('itA')::integer) r));
    PERFORM pg_temp.ok('a range with no tickets is just a total row of zeros',
        (SELECT count(*) = 1 AND bool_and(r.is_total AND r.tickets = 0 AND r.within_48h_share = 0) FROM fn_report_ticket_resolution(1, DATE '2032-05-01', DATE '2032-05-31', NULL) r));
END;
$$;

-- ---------------------------------------------------------------- the range rules, shared by the three reports
DO $$
BEGIN
    PERFORM pg_temp.fails('an end before the start', $q$SELECT 1 FROM fn_report_ticket_resolution(1, DATE '2031-11-30', DATE '2031-11-01', NULL)$q$, '22023', 'to');
    PERFORM pg_temp.fails('more than 366 days', $q$SELECT 1 FROM fn_report_inventory_movement(1, DATE '2031-01-01', DATE '2032-01-02', NULL)$q$, '22023', 'to');
    PERFORM pg_temp.ok('exactly 366 days is allowed', (SELECT count(*) >= 0 FROM fn_report_inventory_movement(1, DATE '2031-01-01', DATE '2032-01-01', NULL)));
    PERFORM pg_temp.fails('one day only (no end)', $q$SELECT 1 FROM fn_report_quotation_conversion(1, DATE '2031-11-01', NULL, 'month')$q$, '22023', 'to');
    PERFORM pg_temp.fails('one day only (no start)', $q$SELECT 1 FROM fn_report_quotation_conversion(1, NULL, DATE '2031-11-30', 'month')$q$, '22023', 'from');
    PERFORM pg_temp.fails('a group that is not month or week', $q$SELECT 1 FROM fn_report_quotation_conversion(1, DATE '2031-11-01', DATE '2031-11-30', 'year')$q$, '22023', 'groupBy');
    PERFORM pg_temp.fails('no group', $q$SELECT 1 FROM fn_report_quotation_conversion(1, DATE '2031-11-01', DATE '2031-11-30', NULL)$q$, '22023', 'groupBy');
    PERFORM pg_temp.ok('with no days at all the report is the current month',
        (SELECT count(*) >= 1 FROM fn_report_quotation_conversion(1, NULL, NULL, 'month')) AND (SELECT count(*) >= 1 FROM fn_report_ticket_resolution(1, NULL, NULL, NULL)));
END;
$$;

-- ---------------------------------------------------------------- another tenant sees nothing of this
DO $$
DECLARE
    a record;
BEGIN
    a := (SELECT x FROM fn_get_dashboard_summary(2, DATE '2031-11-01', DATE '2031-11-30', DATE '2031-10-01', DATE '2031-10-15', pg_temp.asof()) x);
    PERFORM pg_temp.ok('tenant 2''s headline numbers are all zero while tenant 1 has data',
        a.new_leads = 0 AND a.leads_won = 0 AND a.revenue = 0 AND a.open_leads = 0 AND a.dues_total = 0 AND a.open_tickets = 0 AND a.awaiting_reply_count = 0 AND a.low_stock_count = 0);
    PERFORM pg_temp.ok('... and so is every list and report',
        NOT EXISTS (SELECT 1 FROM fn_get_leads_by_source(2, DATE '2031-11-01', DATE '2031-11-30', NULL))
        AND NOT EXISTS (SELECT 1 FROM fn_get_recent_quotations(2, NULL, 20)) AND NOT EXISTS (SELECT 1 FROM fn_get_dashboard_open_tickets(2, 20, pg_temp.asof()))
        AND NOT EXISTS (SELECT 1 FROM fn_get_needs_assignment(2, 20, pg_temp.asof())) AND NOT EXISTS (SELECT 1 FROM fn_get_schedule_today(2, pg_temp.asof()))
        AND NOT EXISTS (SELECT 1 FROM fn_get_technician_workload(2, pg_temp.asof())) AND NOT EXISTS (SELECT 1 FROM fn_get_overdue_payments(2, 20, pg_temp.asof()))
        AND NOT EXISTS (SELECT 1 FROM fn_get_dashboard_low_stock(2, 20)) AND NOT EXISTS (SELECT 1 FROM fn_find_customer(2, 'anil', NULL, 5))
        AND NOT EXISTS (SELECT 1 FROM fn_get_my_tickets(2, pg_temp.ctx('clerk')::integer, 20)) AND NOT EXISTS (SELECT 1 FROM fn_get_leads_to_contact(2, NULL, 20, pg_temp.asof()))
        AND NOT EXISTS (SELECT 1 FROM fn_get_follow_ups_due(2, NULL, 20, pg_temp.asof())) AND NOT EXISTS (SELECT 1 FROM fn_get_expiring_quotations(2, NULL, 20, pg_temp.asof()))
        AND NOT EXISTS (SELECT 1 FROM fn_report_inventory_movement(2, DATE '2031-10-01', DATE '2031-11-30', NULL))
        AND (SELECT sum(created) FROM fn_report_quotation_conversion(2, DATE '2031-10-01', DATE '2031-11-30', 'month') WHERE is_total) = 0
        AND (SELECT sum(tickets) FROM fn_report_ticket_resolution(2, DATE '2031-10-01', DATE '2031-11-30', NULL) WHERE is_total) = 0);
    PERFORM pg_temp.ok('tenant 2''s pipeline lists none of tenant 1''s leads', (SELECT COALESCE(sum(p.lead_count), 0) FROM fn_get_lead_pipeline(2, DATE '2031-11-01', DATE '2031-11-30', NULL) p) = 0);
END;
$$;

SELECT count(*) || ' checks passed' AS result FROM t_pass;
ROLLBACK;
SELECT count(*) AS leads_left_behind FROM leads WHERE lead_no LIKE 'DB%';
