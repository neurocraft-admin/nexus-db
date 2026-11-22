-- DEV ONLY. Sample data for the hand checks of module 11 (Dashboard and reports). NOT a numbered script, NOT recorded in deployment_log,
-- never part of a release. You run it yourself, once, on your development database; it writes no password and creates no user.
--
-- Every row it creates is marked DEMO: names start with "DEMO", document numbers start with "DEMO-" and customer mobiles are in the 70000xxxxx range.
-- dev/demo_dashboard_cleanup.sql removes exactly those rows. Run the seed once; it stops if it finds DEMO rows already there.
--
-- It needs the user names of the test users you made on the Users screen (names, never passwords). All are STAFF-type users:
--   sales1, sales2  two Sales users (their own leads and quotations are the rows that differ between them)
--   clerk           the Clerk user (raises the DEMO tickets)
--   tech1, tech2    optional: two technicians for tasks and assigned tickets (default: sales1 and sales2)
--
--   docker exec -i nexus-pg psql -U postgres -d nexus -v ON_ERROR_STOP=1 \
--     -v sales1=ravi -v sales2=anu -v clerk=meena [-v tech1=suresh -v tech2=anoop] < dev/demo_dashboard_seed.sql
--
-- Dates are relative to today, so the figures are always "this month" and "last month"; run it on the day you test. The tickets and the
-- history rows are written the way the screens write them, so verify_tickets.sql and the other verify scripts still pass with the DEMO rows in.
\if :{?sales1}
\else
    \echo 'Missing -v sales1=<user name>. See the top of this file.'
    \quit
\endif
\if :{?sales2}
\else
    \echo 'Missing -v sales2=<user name>. See the top of this file.'
    \quit
\endif
\if :{?clerk}
\else
    \echo 'Missing -v clerk=<user name>. See the top of this file.'
    \quit
\endif
\if :{?tech1}
\else
    \set tech1 :sales1
\endif
\if :{?tech2}
\else
    \set tech2 :sales2
\endif
\set ON_ERROR_STOP on
SELECT set_config('demo.sales1', :'sales1', false), set_config('demo.sales2', :'sales2', false), set_config('demo.clerk', :'clerk', false),
       set_config('demo.tech1', :'tech1', false), set_config('demo.tech2', :'tech2', false) \gset

BEGIN;
SET LOCAL client_min_messages = warning;
DO $$
DECLARE
    c_tenant CONSTANT integer := 1;
    v_admin integer; v_s1 integer; v_s2 integer; v_clerk integer; v_t1 integer; v_t2 integer;
    v_today date := fn_business_today(c_tenant);
    v_month date := date_trunc('month', fn_business_today(c_tenant))::date;
    v_day integer := extract(day FROM fn_business_today(c_tenant))::integer;
    v_unit_m varchar; v_unit_n varchar;
    v_src_fb integer; v_src_ig integer; v_src_walk integer; v_src_ref integer; v_src_phone integer;
    v_st_new integer; v_st_con integer; v_st_qual integer; v_st_neg integer; v_st_won integer; v_st_lost integer;
    v_it_panel bigint; v_it_inv bigint; v_it_cable bigint; v_it_mc4 bigint; v_it_earth bigint; v_it_batt bigint;
    c bigint[] := ARRAY[]::bigint[];
    v_cust bigint; v_lead bigint; v_q bigint; v_o bigint; v_t bigint; v_k bigint; n integer; m integer; v_when timestamptz; v_amount numeric; v_status varchar;
    v_mid_start timestamptz;
    v_issue integer[];
BEGIN
    IF EXISTS (SELECT 1 FROM leads WHERE lead_no LIKE 'DEMO-%') OR EXISTS (SELECT 1 FROM customers WHERE customer_name LIKE 'DEMO %') THEN
        RAISE EXCEPTION 'DEMO rows are already there. Run dev/demo_dashboard_cleanup.sql first.';
    END IF;
    SELECT u.user_id INTO v_admin FROM users u WHERE u.tenant_id = c_tenant AND u.user_type = 'admin' AND u.is_active ORDER BY u.user_id LIMIT 1;
    SELECT u.user_id INTO v_s1 FROM users u WHERE u.tenant_id = c_tenant AND u.user_name = current_setting('demo.sales1') AND u.user_type = 'staff';
    SELECT u.user_id INTO v_s2 FROM users u WHERE u.tenant_id = c_tenant AND u.user_name = current_setting('demo.sales2') AND u.user_type = 'staff';
    SELECT u.user_id INTO v_clerk FROM users u WHERE u.tenant_id = c_tenant AND u.user_name = current_setting('demo.clerk') AND u.user_type = 'staff';
    SELECT u.user_id INTO v_t1 FROM users u WHERE u.tenant_id = c_tenant AND u.user_name = current_setting('demo.tech1') AND u.user_type = 'staff';
    SELECT u.user_id INTO v_t2 FROM users u WHERE u.tenant_id = c_tenant AND u.user_name = current_setting('demo.tech2') AND u.user_type = 'staff';
    IF v_admin IS NULL OR v_s1 IS NULL OR v_s2 IS NULL OR v_clerk IS NULL OR v_t1 IS NULL OR v_t2 IS NULL THEN
        RAISE EXCEPTION 'A user name was not found, or is not a staff-type user (sales1 %, sales2 %, clerk %, tech1 %, tech2 %).',
            current_setting('demo.sales1'), current_setting('demo.sales2'), current_setting('demo.clerk'), current_setting('demo.tech1'), current_setting('demo.tech2');
    END IF;

    SELECT lead_source_id INTO v_src_fb FROM lead_sources WHERE tenant_id = c_tenant AND source_name = 'Facebook';
    SELECT lead_source_id INTO v_src_ig FROM lead_sources WHERE tenant_id = c_tenant AND source_name = 'Instagram';
    SELECT lead_source_id INTO v_src_walk FROM lead_sources WHERE tenant_id = c_tenant AND source_name = 'Walk-in';
    SELECT lead_source_id INTO v_src_ref FROM lead_sources WHERE tenant_id = c_tenant AND source_name = 'Referral';
    SELECT lead_source_id INTO v_src_phone FROM lead_sources WHERE tenant_id = c_tenant AND source_name = 'Phone';
    SELECT lead_status_id INTO v_st_new FROM lead_statuses WHERE tenant_id = c_tenant AND status_name = 'New';
    SELECT lead_status_id INTO v_st_con FROM lead_statuses WHERE tenant_id = c_tenant AND status_name = 'Contacted';
    SELECT lead_status_id INTO v_st_qual FROM lead_statuses WHERE tenant_id = c_tenant AND status_name = 'Qualified';
    SELECT lead_status_id INTO v_st_neg FROM lead_statuses WHERE tenant_id = c_tenant AND status_name = 'Negotiation';
    SELECT lead_status_id INTO v_st_won FROM lead_statuses WHERE tenant_id = c_tenant AND status_name = 'Won';
    SELECT lead_status_id INTO v_st_lost FROM lead_statuses WHERE tenant_id = c_tenant AND status_name = 'Lost';
    IF v_src_fb IS NULL OR v_st_new IS NULL OR v_st_won IS NULL THEN
        RAISE EXCEPTION 'The standard lead sources and statuses were not found; this seed expects the default master data.';
    END IF;
    SELECT unit_code INTO v_unit_m FROM units WHERE tenant_id = c_tenant AND unit_code = 'm';
    SELECT unit_code INTO v_unit_n FROM units WHERE tenant_id = c_tenant AND unit_code = 'nos';
    v_unit_m := COALESCE(v_unit_m, (SELECT unit_code FROM units WHERE tenant_id = c_tenant ORDER BY unit_code LIMIT 1));
    v_unit_n := COALESCE(v_unit_n, v_unit_m);
    v_issue := ARRAY(SELECT issue_type_id FROM issue_types WHERE tenant_id = c_tenant AND is_active ORDER BY sort_order, issue_type_id LIMIT 5);

    -- Customers: 18 of them, DEMO Customer 01 to 18.
    FOR n IN 1..18 LOOP
        INSERT INTO customers (tenant_id, customer_name, mobile, address)
        VALUES (c_tenant, 'DEMO Customer ' || lpad(n::text, 2, '0'), '70000' || lpad(n::text, 5, '0'),
                (ARRAY['Naruvamoodu', 'Marthandam', 'Kuzhithurai', 'Thuckalay', 'Nagercoil', 'Parassala'])[1 + n % 6] || ', Kanyakumari')
        RETURNING customer_id INTO v_cust;
        c := c || v_cust;
    END LOOP;

    -- Items and their stock (a purchase in and an order out, so the ledger adds up to the stock shown).
    INSERT INTO items (tenant_id, item_code, item_name, unit, cost_price, selling_price, reorder_level, current_stock)
    VALUES (c_tenant, 'DEMO-PANEL540', 'DEMO Solar panel 540 W', v_unit_n, 14000, 17500, 20, 8) RETURNING item_id INTO v_it_panel;
    INSERT INTO items (tenant_id, item_code, item_name, unit, cost_price, selling_price, reorder_level, current_stock)
    VALUES (c_tenant, 'DEMO-HYB5K', 'DEMO Hybrid inverter 5 kW', v_unit_n, 62000, 74000, 4, 2) RETURNING item_id INTO v_it_inv;
    INSERT INTO items (tenant_id, item_code, item_name, unit, cost_price, selling_price, reorder_level, current_stock)
    VALUES (c_tenant, 'DEMO-DCCABLE4', 'DEMO DC cable 4 sq mm', v_unit_m, 38, 52, 300, 120) RETURNING item_id INTO v_it_cable;
    INSERT INTO items (tenant_id, item_code, item_name, unit, cost_price, selling_price, reorder_level, current_stock)
    VALUES (c_tenant, 'DEMO-MC4', 'DEMO MC4 connector pair', v_unit_n, 85, 120, 60, 25) RETURNING item_id INTO v_it_mc4;
    INSERT INTO items (tenant_id, item_code, item_name, unit, cost_price, selling_price, reorder_level, current_stock)
    VALUES (c_tenant, 'DEMO-EARTH', 'DEMO Earthing kit', v_unit_n, 900, 1350, 10, 3) RETURNING item_id INTO v_it_earth;
    INSERT INTO items (tenant_id, item_code, item_name, unit, cost_price, selling_price, reorder_level, current_stock)
    VALUES (c_tenant, 'DEMO-BATT150', 'DEMO Battery 150 Ah', v_unit_n, 11000, 14500, 4, 12) RETURNING item_id INTO v_it_batt;
    INSERT INTO stock_movements (tenant_id, item_id, movement_type, quantity, signed_quantity, unit_cost, reference_type, note, created_by, created_at)
    SELECT c_tenant, i.item_id, 'in', i.current_stock + 10, i.current_stock + 10, i.cost_price, 'purchase', 'DEMO seed', v_admin, now() - interval '40 days'
      FROM items i WHERE i.item_code LIKE 'DEMO-%';
    INSERT INTO stock_movements (tenant_id, item_id, movement_type, quantity, signed_quantity, reference_type, note, created_by, created_at)
    SELECT c_tenant, i.item_id, 'out', 10, -10, 'order', 'DEMO seed', v_admin, now() - interval '12 days' FROM items i WHERE i.item_code LIKE 'DEMO-%';

    -- Leads. Sales user 1 and 2 hold their own; the rest belong to nobody in particular (company-wide numbers).
    -- (number, name, source, status, owner, created days ago, follow-up offset in days or null)
    CREATE TEMP TABLE demo_leads (no integer, src integer, st integer, owner integer, ago integer, follow integer, expected numeric) ON COMMIT DROP;
    INSERT INTO demo_leads VALUES
        (1, v_src_fb, v_st_new, v_s1, 4, NULL, 345000), (2, v_src_ref, v_st_new, v_s1, 3, NULL, 210000), (3, v_src_ig, v_st_new, v_s1, 2, NULL, 680000),
        (4, v_src_walk, v_st_new, v_s1, 1, NULL, NULL), (5, v_src_phone, v_st_con, v_s1, 9, -3, 450000), (6, v_src_fb, v_st_qual, v_s1, 12, 0, 495000),
        (7, v_src_ref, v_st_neg, v_s1, 15, 2, 345000), (8, v_src_ig, v_st_con, v_s1, 6, -1, 210000),
        (9, v_src_fb, v_st_new, v_s2, 3, NULL, 225000), (10, v_src_walk, v_st_con, v_s2, 8, 1, 330000), (11, v_src_ref, v_st_qual, v_s2, 11, NULL, 495000),
        (12, v_src_fb, v_st_neg, v_s2, 14, 0, 680000),
        (13, v_src_fb, v_st_new, NULL, 5, NULL, NULL), (14, v_src_ig, v_st_con, NULL, 7, -2, 210000), (15, v_src_fb, v_st_qual, NULL, 10, NULL, 345000),
        (16, v_src_ref, v_st_neg, NULL, 13, 3, 495000), (17, v_src_phone, v_st_new, NULL, 2, NULL, NULL), (18, v_src_ig, v_st_con, NULL, 16, NULL, 225000),
        (19, v_src_fb, v_st_qual, v_admin, 18, NULL, 330000), (20, v_src_walk, v_st_new, NULL, 20, NULL, NULL);
    -- Won and lost leads, closed this month and last month.
    INSERT INTO demo_leads VALUES (21, v_src_ref, v_st_won, v_s1, 6, NULL, 920000), (22, v_src_fb, v_st_won, v_s1, 8, NULL, 345000), (23, v_src_ref, v_st_won, v_s2, 9, NULL, 210000),
        (24, v_src_ig, v_st_lost, v_s1, 10, NULL, 225000), (25, v_src_fb, v_st_lost, v_s2, 12, NULL, 330000), (26, v_src_walk, v_st_won, NULL, 14, NULL, 680000),
        (27, v_src_fb, v_st_lost, NULL, 17, NULL, 210000), (28, v_src_ref, v_st_won, NULL, 40, NULL, 495000), (29, v_src_fb, v_st_new, NULL, 38, NULL, NULL),
        (30, v_src_ig, v_st_con, NULL, 42, NULL, 345000);
    FOR n IN SELECT no FROM demo_leads ORDER BY no LOOP
        INSERT INTO leads (tenant_id, lead_no, lead_name, mobile, lead_source_id, lead_status_id, assigned_to, expected_value, next_follow_up_date, created_by, is_closed, closed_at, created_at)
        SELECT c_tenant, 'DEMO-LD-' || lpad(d.no::text, 3, '0'),
               'DEMO ' || (ARRAY['Mohan Pillai', 'Lekshmi S', 'Praveen K', 'Divya R', 'Anil Kumar', 'Sheela Nair', 'Rajesh Menon', 'Geetha Varma', 'Joseph Thomas', 'Rejin T'])[1 + d.no % 10] || ' ' || d.no,
               '70001' || lpad(d.no::text, 5, '0'), d.src, d.st, d.owner, d.expected, CASE WHEN d.follow IS NOT NULL THEN v_today + d.follow END, COALESCE(d.owner, v_admin),
               s.is_won OR s.is_lost, CASE WHEN s.is_won OR s.is_lost THEN now() - make_interval(days => GREATEST(d.ago - 2, 0)) END,
               now() - make_interval(days => d.ago, hours => d.no % 7)
          FROM demo_leads d JOIN lead_statuses s ON s.lead_status_id = d.st WHERE d.no = n
         RETURNING lead_id INTO v_lead;
        INSERT INTO lead_activities (tenant_id, lead_id, activity_type, new_value, note, created_by, created_at)
        SELECT c_tenant, l.lead_id, 'created', NULL, 'DEMO lead', COALESCE(l.assigned_to, v_admin), l.created_at FROM leads l WHERE l.lead_id = v_lead;
    END LOOP;

    -- Quotations: sent ones expiring soon (own scope), drafts, approved and rejected ones, for both sales users and the company.
    CREATE TEMP TABLE demo_quotes (no integer, owner integer, lead_no integer, st varchar, ago integer, valid_in integer, amount numeric, label text) ON COMMIT DROP;
    INSERT INTO demo_quotes VALUES
        (1, v_s1, 1, 'sent', 3, 2, 345000, '5 kW on-grid, Standard'), (2, v_s1, NULL, 'approved', 8, 22, 210000, '3 kW on-grid, Basic'), (3, v_s1, 6, 'draft', 1, 29, 495000, '5 kW hybrid, Custom'),
        (4, v_s1, NULL, 'rejected', 20, 10, 225000, '3 kW on-grid, Basic'), (5, v_s1, 7, 'sent', 5, 3, 680000, '10 kW commercial, Premium'),
        (6, v_s2, NULL, 'sent', 4, 5, 210000, '3 kW on-grid, Basic'), (7, v_s2, 12, 'sent', 6, 3, 330000, '4 kW on-grid, Standard'), (8, v_s2, NULL, 'draft', 1, 30, 495000, '5 kW hybrid, Standard'),
        (9, v_admin, NULL, 'sent', 2, 8, 450000, '6 kW on-grid, Premium'), (10, v_admin, NULL, 'sent', 9, 1, 225000, '3 kW on-grid, Basic'), (11, v_admin, NULL, 'approved', 11, 19, 760000, '12 kW commercial'),
        (12, v_admin, NULL, 'rejected', 25, 5, 130000, '2 kW on-grid');
    FOR n IN SELECT no FROM demo_quotes ORDER BY no LOOP
        INSERT INTO quotations (tenant_id, quotation_no, customer_id, lead_id, status, quotation_date, valid_until, subtotal, total_amount, notes, created_by, sent_at, decided_at, created_at)
        SELECT c_tenant, 'DEMO-QT-' || lpad(q.no::text, 3, '0'), c[1 + q.no % 18], (SELECT l.lead_id FROM leads l WHERE l.lead_no = 'DEMO-LD-' || lpad(q.lead_no::text, 3, '0')),
               q.st, v_today - q.ago, v_today + q.valid_in, q.amount, q.amount, 'DEMO ' || q.label, q.owner,
               CASE WHEN q.st <> 'draft' THEN now() - make_interval(days => q.ago) END, CASE WHEN q.st IN ('approved', 'rejected') THEN now() - make_interval(days => GREATEST(q.ago - 1, 0)) END,
               now() - make_interval(days => q.ago)
          FROM demo_quotes q WHERE q.no = n RETURNING quotation_id INTO v_q;
        INSERT INTO quotation_lines (tenant_id, quotation_id, line_type, description, unit, quantity, unit_price, line_total, sort_order)
        SELECT c_tenant, v_q, 'custom', 'DEMO ' || q.label, 'nos', 1, q.amount, q.amount, 1 FROM demo_quotes q WHERE q.no = n;
        INSERT INTO quotation_status_log (tenant_id, quotation_id, from_status, to_status, changed_by, changed_at, note)
        SELECT c_tenant, v_q, NULL, 'draft', q.owner, now() - make_interval(days => q.ago), 'DEMO' FROM demo_quotes q WHERE q.no = n;
        IF EXISTS (SELECT 1 FROM demo_quotes q WHERE q.no = n AND q.st <> 'draft') THEN
            INSERT INTO quotation_status_log (tenant_id, quotation_id, from_status, to_status, changed_by, changed_at, note)
            SELECT c_tenant, v_q, 'draft', 'sent', q.owner, now() - make_interval(days => q.ago), 'DEMO' FROM demo_quotes q WHERE q.no = n;
        END IF;
    END LOOP;

    -- Revenue: two fulfilled orders (each from a converted quotation) in each of the last six months, growing towards the present.
    FOR m IN 0..5 LOOP
        FOR n IN 1..2 LOOP
            v_when := (date_trunc('month', v_today - make_interval(months => m))::date + CASE WHEN n = 1 THEN 2 ELSE 11 END)::timestamptz;
            IF m = 0 AND v_when > now() THEN
                v_when := now() - interval '1 day';
            END IF;
            v_amount := (ARRAY[120000, 148000, 131000, 172000, 163000, 198000])[6 - m] + n * 21000;
            INSERT INTO quotations (tenant_id, quotation_no, customer_id, status, quotation_date, valid_until, subtotal, total_amount, notes, created_by, sent_at, decided_at, created_at)
            VALUES (c_tenant, 'DEMO-QT-R' || m || n, c[1 + (m * 2 + n) % 18], 'converted', (v_when - interval '6 days')::date, (v_when + interval '24 days')::date, v_amount, v_amount,
                    'DEMO order history', v_admin, v_when - interval '6 days', v_when - interval '3 days', v_when - interval '7 days') RETURNING quotation_id INTO v_q;
            INSERT INTO quotation_lines (tenant_id, quotation_id, line_type, description, unit, quantity, unit_price, line_total, sort_order)
            VALUES (c_tenant, v_q, 'custom', 'DEMO solar installation', 'nos', 1, v_amount, v_amount, 1);
            INSERT INTO quotation_status_log (tenant_id, quotation_id, from_status, to_status, changed_by, changed_at, note)
            VALUES (c_tenant, v_q, NULL, 'draft', v_admin, v_when - interval '7 days', 'DEMO'), (c_tenant, v_q, 'draft', 'sent', v_admin, v_when - interval '6 days', 'DEMO'),
                   (c_tenant, v_q, 'sent', 'approved', v_admin, v_when - interval '3 days', 'DEMO'), (c_tenant, v_q, 'approved', 'converted', v_admin, v_when - interval '2 days', 'DEMO');
            INSERT INTO orders (tenant_id, order_no, quotation_id, customer_id, status, payment_mode, total_amount, fulfilled_at, created_by, created_at)
            VALUES (c_tenant, 'DEMO-OR-' || m || n, v_q, c[1 + (m * 2 + n) % 18], 'fulfilled', 'paid', v_amount, v_when, v_admin, v_when - interval '2 days') RETURNING order_id INTO v_o;
            INSERT INTO order_lines (tenant_id, order_id, line_type, description, unit, quantity, unit_price, line_total, sort_order)
            VALUES (c_tenant, v_o, 'custom', 'DEMO solar installation', 'nos', 1, v_amount, v_amount, 1);
            INSERT INTO order_status_log (tenant_id, order_id, from_status, to_status, changed_by, changed_at, note)
            VALUES (c_tenant, v_o, NULL, 'new', v_admin, v_when - interval '2 days', 'DEMO'), (c_tenant, v_o, 'new', 'fulfilled', v_admin, v_when, 'DEMO');
        END LOOP;
    END LOOP;

    -- Dues: customers who owe money past the 30-day credit terms (and two who do not).
    CREATE TEMP TABLE demo_dues (cust integer, charge numeric, charge_ago integer, paid numeric, paid_ago integer) ON COMMIT DROP;
    INSERT INTO demo_dues VALUES (1, 180000, 64, NULL, NULL), (2, 95000, 51, NULL, NULL), (3, 70000, 42, NULL, NULL), (4, 40000, 35, NULL, NULL), (5, 20000, 10, NULL, NULL), (6, 50000, 70, 50000, 60);
    INSERT INTO customer_credit_ledgers (tenant_id, customer_id, entry_type, amount, note, created_by, created_at)
    SELECT c_tenant, c[d.cust], 'charge', d.charge, 'DEMO credit sale', v_admin, now() - make_interval(days => d.charge_ago) FROM demo_dues d;
    INSERT INTO customer_credit_ledgers (tenant_id, customer_id, entry_type, amount, note, created_by, created_at)
    SELECT c_tenant, c[d.cust], 'payment', d.paid, 'DEMO payment', v_admin, now() - make_interval(days => d.paid_ago) FROM demo_dues d WHERE d.paid IS NOT NULL;
    UPDATE customers cu SET credit_balance = d.charge - COALESCE(d.paid, 0) FROM demo_dues d WHERE cu.customer_id = c[d.cust];

    -- Tickets (each active one on its own customer). (number, customer index, source, raised by, assigned to, status, raised days ago, resolved days after raising, issue index, text)
    CREATE TEMP TABLE demo_tickets (no integer, cust integer, src varchar, by_user integer, assignee integer, st varchar, ago integer, text text) ON COMMIT DROP;
    INSERT INTO demo_tickets VALUES
        (1, 1, 'internal', v_clerk, NULL, 'open', 0, 'Inverter error E04, no generation'), (2, 2, 'internal', v_clerk, NULL, 'open', 3, 'Panel cleaning request'),
        (3, 3, 'internal', v_clerk, v_t1, 'in_progress', 2, 'Monitoring app shows offline'), (4, 4, 'internal', v_clerk, v_t2, 'open', 9, 'Net-meter reading mismatch'),
        (5, 5, 'internal', v_clerk, v_t1, 'resolved', 4, 'Low generation after rain'), (6, 6, 'portal', NULL, NULL, 'open', 2, 'Inverter beeping every few minutes'),
        (7, 7, 'portal', NULL, v_t1, 'in_progress', 8, 'Output is half of what it was last year'), (8, 8, 'portal', NULL, NULL, 'open', 5, 'Battery backup not lasting the night'),
        (9, 9, 'internal', v_admin, v_t2, 'in_progress', 6, 'DEMO ticket raised by the administrator'), (10, 10, 'portal', NULL, v_t2, 'resolved', 12, 'Wi-fi dongle replaced'),
        (11, 11, 'internal', v_clerk, v_t2, 'closed', 20, 'Earth wire loose, fixed on site');
    FOR n IN SELECT no FROM demo_tickets ORDER BY no LOOP
        INSERT INTO tickets (tenant_id, ticket_no, customer_id, issue_type_id, description, status, source, assigned_to, resolved_at, closed_at, created_by, created_at)
        SELECT c_tenant, 'DEMO-TK-' || lpad(t.no::text, 3, '0'), c[t.cust], v_issue[1 + t.no % array_length(v_issue, 1)], 'DEMO ' || t.text, t.st, t.src, t.assignee,
               CASE WHEN t.st IN ('resolved', 'closed') THEN now() - make_interval(days => GREATEST(t.ago - 1, 0)) END,
               CASE WHEN t.st = 'closed' THEN now() - make_interval(days => GREATEST(t.ago - 2, 0)) END, t.by_user, now() - make_interval(days => t.ago, hours => t.no)
          FROM demo_tickets t WHERE t.no = n RETURNING ticket_id INTO v_k;
        INSERT INTO ticket_status_history (tenant_id, ticket_id, old_status, new_status, changed_by, note, changed_at)
        SELECT c_tenant, v_k, NULL, 'open', t.by_user, 'DEMO', now() - make_interval(days => t.ago, hours => t.no) FROM demo_tickets t WHERE t.no = n;
        INSERT INTO ticket_status_history (tenant_id, ticket_id, old_status, new_status, assigned_to, changed_by, note, changed_at)
        SELECT c_tenant, v_k, 'open', 'open', t.assignee, v_admin, 'DEMO', now() - make_interval(days => GREATEST(t.ago - 1, 0)) FROM demo_tickets t WHERE t.no = n AND t.assignee IS NOT NULL;
        INSERT INTO ticket_status_history (tenant_id, ticket_id, old_status, new_status, changed_by, note, changed_at)
        SELECT c_tenant, v_k, 'open', 'in_progress', COALESCE(t.assignee, v_admin), 'DEMO', now() - make_interval(days => GREATEST(t.ago - 1, 0)) FROM demo_tickets t WHERE t.no = n AND t.st IN ('in_progress', 'resolved', 'closed');
        INSERT INTO ticket_status_history (tenant_id, ticket_id, old_status, new_status, changed_by, note, changed_at)
        SELECT c_tenant, v_k, 'in_progress', 'resolved', COALESCE(t.assignee, v_admin), 'DEMO', now() - make_interval(days => GREATEST(t.ago - 1, 0)) FROM demo_tickets t WHERE t.no = n AND t.st IN ('resolved', 'closed');
        INSERT INTO ticket_status_history (tenant_id, ticket_id, old_status, new_status, changed_by, note, changed_at)
        SELECT c_tenant, v_k, 'resolved', 'closed', v_admin, 'DEMO', now() - make_interval(days => GREATEST(t.ago - 2, 0)) FROM demo_tickets t WHERE t.no = n AND t.st = 'closed';
    END LOOP;

    -- Tasks: today's visits for the two technicians, one overdue, one done. Times are in the business time zone (India).
    v_mid_start := (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata')) AT TIME ZONE 'Asia/Kolkata';
    CREATE TEMP TABLE demo_tasks (no integer, typ varchar, title text, assignee integer, cust integer, at_ timestamptz, st varchar) ON COMMIT DROP;
    INSERT INTO demo_tasks VALUES
        (1, 'installation', 'Installation, 5 kW on-grid', v_t1, 1, v_mid_start + interval '9 hours', 'in_progress'), (2, 'site_visit', 'Site visit', v_t2, 2, v_mid_start + interval '11 hours 30 minutes', 'assigned'),
        (3, 'service', 'Inverter service', v_t2, 3, v_mid_start + interval '14 hours', 'assigned'), (4, 'service', 'Net-meter inspection', v_t2, 4, v_mid_start - interval '15 hours', 'assigned'),
        (5, 'site_visit', 'Site visit, 10 kW commercial', v_t1, 12, v_mid_start + interval '1 day 10 hours', 'assigned'), (6, 'installation', 'Installation, 3 kW on-grid', v_t1, 13, v_mid_start + interval '8 hours', 'done');
    FOR n IN SELECT no FROM demo_tasks ORDER BY no LOOP
        INSERT INTO tasks (tenant_id, task_no, task_type, title, customer_id, assigned_to, scheduled_at, visit_address, status, completion_note, completed_at, created_by)
        SELECT c_tenant, 'DEMO-TS-' || lpad(t.no::text, 3, '0'), t.typ, 'DEMO ' || t.title, c[t.cust], t.assignee, t.at_, 'DEMO site address, Kanyakumari', t.st,
               CASE WHEN t.st = 'done' THEN 'Done (DEMO)' END, CASE WHEN t.st = 'done' THEN now() END, v_admin
          FROM demo_tasks t WHERE t.no = n RETURNING task_id INTO v_t;
        INSERT INTO task_status_history (tenant_id, task_id, old_status, new_status, assigned_to, changed_by, note, changed_at)
        SELECT c_tenant, v_t, NULL, 'assigned', t.assignee, v_admin, 'DEMO', now() - interval '1 day' FROM demo_tasks t WHERE t.no = n;
        INSERT INTO task_status_history (tenant_id, task_id, old_status, new_status, changed_by, note, changed_at)
        SELECT c_tenant, v_t, 'assigned', 'in_progress', t.assignee, 'DEMO', now() - interval '2 hours' FROM demo_tasks t WHERE t.no = n AND t.st IN ('in_progress', 'done');
        INSERT INTO task_status_history (tenant_id, task_id, old_status, new_status, changed_by, note, changed_at)
        SELECT c_tenant, v_t, 'in_progress', 'done', t.assignee, 'Done (DEMO)', now() FROM demo_tasks t WHERE t.no = n AND t.st = 'done';
    END LOOP;

    RAISE NOTICE 'DEMO data written: 18 customers, 6 items, 30 leads, 24 quotations, 12 orders, 11 tickets, 6 tasks.';
END;
$$;
COMMIT;

SELECT 'customers' AS what, count(*) AS demo_rows FROM customers WHERE customer_name LIKE 'DEMO %'
UNION ALL SELECT 'leads', count(*) FROM leads WHERE lead_no LIKE 'DEMO-%'
UNION ALL SELECT 'quotations', count(*) FROM quotations WHERE quotation_no LIKE 'DEMO-%'
UNION ALL SELECT 'orders', count(*) FROM orders WHERE order_no LIKE 'DEMO-%'
UNION ALL SELECT 'tickets', count(*) FROM tickets WHERE ticket_no LIKE 'DEMO-%'
UNION ALL SELECT 'tasks', count(*) FROM tasks WHERE task_no LIKE 'DEMO-%'
UNION ALL SELECT 'items', count(*) FROM items WHERE item_code LIKE 'DEMO-%';
