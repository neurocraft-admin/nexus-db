-- Module 7 (Tickets): behaviour tests for the database. Everything runs in ONE transaction that is rolled back at the
-- end, so it leaves nothing behind (not even document numbers) and is safe to run on any database that has scripts
-- 00-23 and the function files applied. Stops at the first failure ("FAILED: <what>"); on success prints the count.
--   docker exec -i nexus-pg-test psql -U postgres -d <db> -v ON_ERROR_STOP=1 < tests/test_tickets.sql
-- The one-active-ticket rule under two SIMULTANEOUS submissions needs two sessions: tests/tickets_concurrency.ps1.
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

-- Runs a statement that must be refused with the given SQLSTATE (and, when given, COLUMN, HINT and constraint name).
CREATE FUNCTION pg_temp.fails(p_label text, p_sql text, p_state text, p_column text DEFAULT NULL, p_hint text DEFAULT NULL,
                              p_constraint text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_state text; v_column text; v_detail text; v_constraint text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
        GET STACKED DIAGNOSTICS v_column = COLUMN_NAME, v_detail = PG_EXCEPTION_HINT, v_constraint = CONSTRAINT_NAME;
    END;
    PERFORM pg_temp.ok(p_label || ' [refused with ' || p_state || ', got ' || COALESCE(v_state, 'no error') || ']', v_state = p_state);
    IF p_column IS NOT NULL THEN
        PERFORM pg_temp.ok(p_label || ' [names column ' || p_column || ']', v_column = p_column);
    END IF;
    IF p_hint IS NOT NULL THEN
        PERFORM pg_temp.ok(p_label || ' [hint ' || p_hint || ']', v_detail = p_hint);
    END IF;
    IF p_constraint IS NOT NULL THEN
        PERFORM pg_temp.ok(p_label || ' [by ' || p_constraint || ']', v_constraint = p_constraint);
    END IF;
END;
$$;

-- A successful ticket for the customer saved under that key; returns its id.
CREATE FUNCTION pg_temp.mk(p_customer text, p_issue integer, p_other text, p_source text, p_by integer DEFAULT NULL)
RETURNS bigint LANGUAGE sql AS $$
    SELECT c.ticket_id FROM fn_create_ticket(1, pg_temp.ctx(p_customer), p_issue, p_other, 'Panel output is low', p_source, p_by,
                                             NULL, NULL, NULL, NULL) c
$$;

CREATE FUNCTION pg_temp.new_user(p_name text, p_full text, p_role text, p_type text, p_active boolean) RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO users (tenant_id, user_name, full_name, password_hash, role_id, user_type, is_active)
    SELECT 1, p_name, p_full, 'x', r.role_id, p_type, p_active FROM roles r WHERE r.tenant_id = 1 AND r.role_name = p_role
    RETURNING user_id
$$;

-- Ticket numbers are checked relative to where the counter stands, so this runs on a database that already has tickets.
CREATE FUNCTION pg_temp.base() RETURNS integer LANGUAGE sql AS $$
    SELECT COALESCE((SELECT last_no FROM document_counters WHERE tenant_id = 1 AND doc_type = 'TKT' AND doc_year = extract(year FROM now())::integer), 0)
$$;
CREATE TEMP TABLE t_base AS SELECT pg_temp.base() AS n;
CREATE FUNCTION pg_temp.no(p_n integer) RETURNS text LANGUAGE sql AS
    $$ SELECT 'TKT-' || to_char(now(), 'YYYY') || '-' || lpad(((SELECT n FROM t_base) + p_n)::text, 4, '0') $$;

-- ---------------------------------------------------------------- setup
DO $$
DECLARE
    v_id bigint;
BEGIN
    PERFORM pg_temp.setctx('admin', pg_temp.new_user('tk_admin', 'Deepu Admin', 'Admin', 'admin', true));
    PERFORM pg_temp.setctx('staff1', pg_temp.new_user('tk_staff1', 'Ravi Technician', 'Staff', 'staff', true));
    PERFORM pg_temp.setctx('staff2', pg_temp.new_user('tk_staff2', 'Suma Technician', 'Staff', 'staff', true));
    PERFORM pg_temp.setctx('gone', pg_temp.new_user('tk_gone', 'Left Company', 'Staff', 'staff', false));
    PERFORM pg_temp.setctx('c1', fn_save_customer(1, NULL, 'Anil Kumar', '9876500001', 'Tharayil House, Naruvamoodu'));
    PERFORM pg_temp.setctx('c2', fn_save_customer(1, NULL, 'Bindu Nair', '9876500002', 'Kodungannoor'));
    PERFORM pg_temp.setctx('c3', fn_save_customer(1, NULL, 'Chitra Devi', '9876500003', 'Pattom'));
    PERFORM pg_temp.setctx('c4', fn_save_customer(1, NULL, 'Dinesh Pillai', '9876500004', 'Vattiyoorkavu'));
    PERFORM pg_temp.setctx('c5', fn_save_customer(1, NULL, 'Elsy Thomas', '9876500005', 'Kowdiar'));
    PERFORM pg_temp.setctx('c6', fn_save_customer(1, NULL, 'Femi Joseph', '9876500006', 'Nemom'));
    PERFORM pg_temp.setctx('c7', fn_save_customer(1, NULL, 'Gopan Das', '9876500007', 'Peroorkada'));
    UPDATE customers SET is_active = false WHERE customer_id = pg_temp.ctx('c5');
    INSERT INTO customers (tenant_id, customer_name, mobile) VALUES (2, 'Other Tenant Customer', '9876500099') RETURNING customer_id INTO v_id;
    PERFORM pg_temp.setctx('t2customer', v_id);
    PERFORM pg_temp.setctx('t2issue', fn_save_issue_type(2, NULL, 'Tenant two issue', 10, true));
    PERFORM pg_temp.setctx('it_not_working', (SELECT t.issue_type_id FROM issue_types t WHERE t.tenant_id = 1 AND t.issue_type_name = 'Not working'));
    PERFORM pg_temp.setctx('it_inverter', (SELECT t.issue_type_id FROM issue_types t WHERE t.tenant_id = 1 AND t.issue_type_name = 'Inverter fault'));
END;
$$;

-- ---------------------------------------------------------------- issue types
DO $$
DECLARE
    v_id integer;
BEGIN
    PERFORM pg_temp.ok('five issue types are seeded', (SELECT count(*) FROM fn_get_issue_types(1, true)) = 5);
    PERFORM pg_temp.ok('there is no "Other" issue type (Other is free text)', NOT EXISTS (SELECT 1 FROM issue_types WHERE lower(issue_type_name) = 'other'));
    v_id := fn_save_issue_type(1, NULL, '  Battery issue ', 60, true);
    PERFORM pg_temp.ok('a new issue type is added, trimmed', (SELECT issue_type_name FROM fn_get_issue_types(1, false) WHERE issue_type_id = v_id) = 'Battery issue');
    PERFORM fn_save_issue_type(1, v_id, 'Battery fault', 60, false);
    PERFORM pg_temp.ok('an issue type can be renamed and switched off', (SELECT issue_type_name FROM fn_get_issue_types(1, false) WHERE issue_type_id = v_id) = 'Battery fault');
    PERFORM pg_temp.ok('a switched-off type leaves the active list', NOT EXISTS (SELECT 1 FROM fn_get_issue_types(1, true) WHERE issue_type_id = v_id));
    PERFORM pg_temp.setctx('it_off', v_id);
    PERFORM pg_temp.fails('a duplicate name, ignoring case', $q$SELECT fn_save_issue_type(1, NULL, 'NOT WORKING', 1, true)$q$, '23505', NULL, NULL, 'uq_issue_types_tenant_name');
    PERFORM pg_temp.fails('a blank name', $q$SELECT fn_save_issue_type(1, NULL, '   ', 1, true)$q$, '22023', 'issueTypeName');
    PERFORM pg_temp.fails('a name over 100 characters', format($q$SELECT fn_save_issue_type(1, NULL, %L, 1, true)$q$, repeat('x', 101)), '22023', 'issueTypeName');
    PERFORM pg_temp.fails('an unknown issue type on update', $q$SELECT fn_save_issue_type(1, 999999, 'x', 1, true)$q$, 'P0002');
    PERFORM pg_temp.fails('another tenant''s issue type cannot be updated', format($q$SELECT fn_save_issue_type(1, %s, 'x', 1, true)$q$, pg_temp.ctx('t2issue')), 'P0002');
    PERFORM pg_temp.ok('another tenant sees only its own types', (SELECT count(*) FROM fn_get_issue_types(2, false)) = 1);
END;
$$;

-- ---------------------------------------------------------------- creating a ticket
DO $$
DECLARE
    v_ticket bigint;
    v_year   text := to_char(now(), 'YYYY');
BEGIN
    v_ticket := pg_temp.mk('c1', pg_temp.ctx('it_not_working')::integer, NULL, 'portal');
    PERFORM pg_temp.setctx('t1', v_ticket);
    PERFORM pg_temp.ok('the first ticket of the test is the next number, TKT-yyyy-nnnn (four digits)', (SELECT ticket_no FROM tickets WHERE ticket_id = v_ticket) = pg_temp.no(1));
    PERFORM pg_temp.ok('a new ticket is open, from the portal, with no creator',
        (SELECT status = 'open' AND source = 'portal' AND created_by IS NULL AND assigned_to IS NULL AND resolved_at IS NULL AND closed_at IS NULL
           FROM tickets WHERE ticket_id = v_ticket));
    PERFORM pg_temp.ok('it has exactly one history row: no old status, new status open',
        (SELECT count(*) = 1 AND bool_and(old_status IS NULL AND new_status = 'open' AND changed_by IS NULL AND assigned_to IS NULL)
           FROM ticket_status_history WHERE ticket_id = v_ticket));
    PERFORM pg_temp.ok('the detail shows the customer, the issue type name and the description',
        (SELECT customer_name = 'Anil Kumar' AND customer_mobile = '9876500001' AND issue_text = 'Not working' AND description = 'Panel output is low'
           FROM fn_get_ticket_by_id(1, v_ticket, NULL)));
    PERFORM pg_temp.fails('a second ticket for the same customer is refused, naming the first',
        format($q$SELECT pg_temp.mk('c1', %s, NULL, 'portal')$q$, pg_temp.ctx('it_not_working')), 'NX409', 'customerId', pg_temp.no(1));
    v_ticket := pg_temp.mk('c2', pg_temp.ctx('it_inverter')::integer, NULL, 'portal');
    PERFORM pg_temp.setctx('t2', v_ticket);
    PERFORM pg_temp.ok('the refused ticket did not use up a number: the next one is 0002', (SELECT ticket_no FROM tickets WHERE ticket_id = v_ticket) = pg_temp.no(2));
    v_ticket := pg_temp.mk('c6', NULL, '  Strange noise from the meter ', 'internal', pg_temp.ctx('admin')::integer);
    PERFORM pg_temp.setctx('t6', v_ticket);
    PERFORM pg_temp.ok('a staff ticket records its creator and the trimmed free text',
        (SELECT created_by = pg_temp.ctx('admin') AND source = 'internal' AND issue_type_id IS NULL AND other_issue_text = 'Strange noise from the meter'
                AND issue_text = 'Strange noise from the meter' FROM fn_get_ticket_by_id(1, v_ticket, NULL)));
    PERFORM pg_temp.ok('the creator is in the first history row', (SELECT changed_by FROM ticket_status_history WHERE ticket_id = v_ticket) = pg_temp.ctx('admin'));
END;
$$;

DO $$
DECLARE
    v_c4 text := pg_temp.ctx('c4')::text;
    v_it text := pg_temp.ctx('it_not_working')::text;
BEGIN
    PERFORM pg_temp.fails('an issue type and free text together', format($q$SELECT fn_create_ticket(1, %s, %s, 'x', 'd', 'portal', NULL, NULL, NULL, NULL, NULL)$q$, v_c4, v_it), '22023', 'issueTypeId');
    PERFORM pg_temp.fails('neither an issue type nor free text', format($q$SELECT fn_create_ticket(1, %s, NULL, '  ', 'd', 'portal', NULL, NULL, NULL, NULL, NULL)$q$, v_c4), '22023', 'issueTypeId');
    PERFORM pg_temp.fails('free text over 100 characters', format($q$SELECT fn_create_ticket(1, %s, NULL, %L, 'd', 'portal', NULL, NULL, NULL, NULL, NULL)$q$, v_c4, repeat('x', 101)), '22023', 'otherIssueText');
    PERFORM pg_temp.fails('a description over 500 characters', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, %L, 'portal', NULL, NULL, NULL, NULL, NULL)$q$, v_c4, v_it, repeat('x', 501)), '22023', 'description');
    PERFORM pg_temp.fails('a blank description', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, '   ', 'portal', NULL, NULL, NULL, NULL, NULL)$q$, v_c4, v_it), '22023', 'description');
    PERFORM pg_temp.fails('a source that is neither portal nor internal', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'email', NULL, NULL, NULL, NULL, NULL)$q$, v_c4, v_it), '22023', 'source');
    PERFORM pg_temp.fails('a staff ticket without its creator', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'internal', NULL, NULL, NULL, NULL, NULL)$q$, v_c4, v_it), '22023', 'createdBy');
    PERFORM pg_temp.fails('a portal ticket with a creator', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'portal', %s, NULL, NULL, NULL, NULL)$q$, v_c4, v_it, pg_temp.ctx('admin')), '22023', 'createdBy');
    PERFORM pg_temp.fails('an issue type that is switched off', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'portal', NULL, NULL, NULL, NULL, NULL)$q$, v_c4, pg_temp.ctx('it_off')), 'NX409', 'issueTypeId');
    PERFORM pg_temp.fails('an unknown issue type', format($q$SELECT fn_create_ticket(1, %s, 999999, NULL, 'd', 'portal', NULL, NULL, NULL, NULL, NULL)$q$, v_c4), 'P0002', 'issueTypeId');
    PERFORM pg_temp.fails('another tenant''s issue type', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'portal', NULL, NULL, NULL, NULL, NULL)$q$, v_c4, pg_temp.ctx('t2issue')), 'P0002', 'issueTypeId');
    PERFORM pg_temp.fails('an unknown customer', format($q$SELECT fn_create_ticket(1, 999999, %s, NULL, 'd', 'portal', NULL, NULL, NULL, NULL, NULL)$q$, v_it), 'P0002', 'customerId');
    PERFORM pg_temp.fails('another tenant''s customer', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'portal', NULL, NULL, NULL, NULL, NULL)$q$, pg_temp.ctx('t2customer'), v_it), 'P0002', 'customerId');
    PERFORM pg_temp.fails('a deactivated customer', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'portal', NULL, NULL, NULL, NULL, NULL)$q$, pg_temp.ctx('c5'), v_it), 'NX409', 'customerId');
    PERFORM pg_temp.fails('an attachment that is only partly given', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'portal', NULL, 'a.pdf', NULL, 'application/pdf', 10)$q$, v_c4, v_it), '22023', 'attachment');
    PERFORM pg_temp.fails('an attachment of an unsupported type', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'portal', NULL, 'a.exe', 'rnd1', 'application/x-msdownload', 10)$q$, v_c4, v_it), '23514');
    PERFORM pg_temp.fails('an empty attachment', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'portal', NULL, 'a.pdf', 'rnd2', 'application/pdf', 0)$q$, v_c4, v_it), '23514');
    PERFORM pg_temp.fails('an attachment over 5 MB', format($q$SELECT fn_create_ticket(1, %s, %s, NULL, 'd', 'portal', NULL, 'a.pdf', 'rnd3', 'application/pdf', 5242881)$q$, v_c4, v_it), '23514');
    PERFORM pg_temp.ok('none of the refused tickets left anything behind', NOT EXISTS (SELECT 1 FROM tickets WHERE customer_id = pg_temp.ctx('c4')));
    PERFORM c.ticket_id FROM fn_create_ticket(1, pg_temp.ctx('c4'), pg_temp.ctx('it_not_working')::integer, NULL, repeat('d', 500), 'portal', NULL, NULL, NULL, NULL, NULL) c;
    PERFORM pg_temp.ok('a description of exactly 500 characters is accepted',
        (SELECT length(t.description) FROM tickets t WHERE t.customer_id = pg_temp.ctx('c4')) = 500);
    UPDATE tickets SET status = 'closed', closed_at = now() WHERE customer_id = pg_temp.ctx('c4');   -- c4 is not needed again
END;
$$;

DO $$
DECLARE
    v_ticket bigint;
    v_att    bigint;
BEGIN
    SELECT c.ticket_id INTO v_ticket FROM fn_create_ticket(1, pg_temp.ctx('c3'), pg_temp.ctx('it_inverter')::integer, NULL, 'Inverter shows E04',
        'portal', NULL, '../../evil.pdf', 'f3a9c1e2b4d54c7e8a1b0c2d3e4f5a6b.pdf', 'application/pdf', 5242880) c;
    PERFORM pg_temp.setctx('t3', v_ticket);
    PERFORM pg_temp.ok('a ticket with a file of exactly 5 MB is created together with its attachment row',
        (SELECT count(*) = 1 AND bool_and(original_name = '../../evil.pdf' AND size_bytes = 5242880) FROM fn_get_ticket_attachments(1, v_ticket, NULL)));
    SELECT a.attachment_id INTO v_att FROM fn_get_ticket_attachments(1, v_ticket, NULL) a;
    PERFORM pg_temp.setctx('att3', v_att);
    PERFORM pg_temp.ok('the listing never gives the stored name',
        NOT EXISTS (SELECT 1 FROM jsonb_object_keys((SELECT to_jsonb(a) FROM fn_get_ticket_attachments(1, v_ticket, NULL) a)) k WHERE k = 'stored_name'));
    PERFORM pg_temp.ok('the download gives the stored name and type',
        (SELECT stored_name = 'f3a9c1e2b4d54c7e8a1b0c2d3e4f5a6b.pdf' AND content_type = 'application/pdf' FROM fn_get_ticket_attachment(1, v_ticket, v_att, NULL)));
    PERFORM pg_temp.ok('the file does not belong to another ticket', NOT EXISTS (SELECT 1 FROM fn_get_ticket_attachment(1, pg_temp.ctx('t1'), v_att, NULL)));
    PERFORM pg_temp.fails('a stored name cannot be used twice',
        format($q$SELECT fn_add_ticket_attachment(1, %s, 'b.pdf', 'f3a9c1e2b4d54c7e8a1b0c2d3e4f5a6b.pdf', 'application/pdf', 10)$q$, pg_temp.ctx('t1')), '23505');
    PERFORM pg_temp.fails('a file for an unknown ticket', $q$SELECT fn_add_ticket_attachment(1, 999999, 'b.pdf', 'zz1.pdf', 'application/pdf', 10)$q$, 'P0002');
END;
$$;

-- ---------------------------------------------------------------- the status rules: every one of the 16 moves
DO $$
DECLARE
    v_old text; v_new text; v_state text;
    c_all     CONSTANT text[] := ARRAY['open', 'in_progress', 'resolved', 'closed'];
    c_allowed CONSTANT text[] := ARRAY['open>in_progress', 'in_progress>resolved', 'resolved>closed', 'resolved>in_progress', 'open>closed'];
    v_checked integer := 0;
BEGIN
    FOREACH v_old IN ARRAY c_all LOOP
        FOREACH v_new IN ARRAY c_all LOOP
            v_state := NULL;
            BEGIN
                CALL sp_check_ticket_status_move(v_old, v_new, 'a note');
            EXCEPTION WHEN OTHERS THEN
                v_state := SQLSTATE;
            END;
            PERFORM pg_temp.ok(format('move %s -> %s is %s', v_old, v_new, CASE WHEN (v_old || '>' || v_new) = ANY (c_allowed) THEN 'allowed' ELSE 'refused' END),
                CASE WHEN (v_old || '>' || v_new) = ANY (c_allowed) THEN v_state IS NULL ELSE v_state = 'NX409' END);
            v_checked := v_checked + 1;
        END LOOP;
    END LOOP;
    PERFORM pg_temp.ok('all 16 moves were checked', v_checked = 16);
    PERFORM pg_temp.fails('open -> closed without a note', $q$CALL sp_check_ticket_status_move('open', 'closed', NULL)$q$, '22023', 'note');
    PERFORM pg_temp.fails('open -> closed with a blank note', $q$CALL sp_check_ticket_status_move('open', 'closed', '   ')$q$, '22023', 'note');
    PERFORM pg_temp.fails('an unknown status', $q$CALL sp_check_ticket_status_move('open', 'done', NULL)$q$, '22023', 'status');
    PERFORM pg_temp.fails('a note over 500 characters', format($q$CALL sp_check_ticket_status_move('open', 'in_progress', %L)$q$, repeat('n', 501)), '22023', 'note');
    CALL sp_check_ticket_status_move('resolved', 'closed', NULL);
    CALL sp_check_ticket_status_move('in_progress', 'resolved', NULL);
    PERFORM pg_temp.ok('resolved -> closed and in_progress -> resolved need no note', true);
END;
$$;

-- ---------------------------------------------------------------- one ticket through its life (ticket 1, customer 1)
DO $$
DECLARE
    v_t  bigint := pg_temp.ctx('t1');
    v_by integer := pg_temp.ctx('admin');
    v_year text := to_char(now(), 'YYYY');
    v_t1b bigint;
BEGIN
    CALL sp_change_ticket_status(1, v_t, 'in_progress', NULL, v_by, NULL);
    PERFORM pg_temp.ok('open -> in progress: status changed, one more history row with who',
        (SELECT status = 'in_progress' AND resolved_at IS NULL FROM tickets WHERE ticket_id = v_t)
        AND (SELECT count(*) = 2 AND (array_agg(old_status || '>' || new_status ORDER BY history_id))[2] = 'open>in_progress'
                AND (array_agg(changed_by ORDER BY history_id))[2] = v_by FROM ticket_status_history WHERE ticket_id = v_t));
    PERFORM pg_temp.fails('the same status again', format($q$CALL sp_change_ticket_status(1, %s, 'in_progress', NULL, %s, NULL)$q$, v_t, v_by), 'NX409', 'status');
    PERFORM pg_temp.fails('in progress -> closed is not allowed', format($q$CALL sp_change_ticket_status(1, %s, 'closed', 'give up', %s, NULL)$q$, v_t, v_by), 'NX409', 'status');
    PERFORM pg_temp.fails('in progress -> open is not allowed', format($q$CALL sp_change_ticket_status(1, %s, 'open', NULL, %s, NULL)$q$, v_t, v_by), 'NX409', 'status');
    PERFORM pg_temp.fails('an unknown status', format($q$CALL sp_change_ticket_status(1, %s, 'done', NULL, %s, NULL)$q$, v_t, v_by), '22023', 'status');
    PERFORM pg_temp.fails('an unknown ticket', format($q$CALL sp_change_ticket_status(1, 999999, 'resolved', NULL, %s, NULL)$q$, v_by), 'P0002');
    PERFORM pg_temp.ok('refused moves wrote nothing', (SELECT count(*) FROM ticket_status_history WHERE ticket_id = v_t) = 2);
    CALL sp_change_ticket_status(1, v_t, 'resolved', '  Inverter reset, wiring tightened ', v_by, NULL);
    PERFORM pg_temp.ok('resolving stamps resolved_at, keeps closed_at empty and keeps the trimmed note',
        (SELECT resolved_at IS NOT NULL AND closed_at IS NULL FROM tickets WHERE ticket_id = v_t)
        AND (SELECT note FROM ticket_status_history WHERE ticket_id = v_t ORDER BY history_id DESC LIMIT 1) = 'Inverter reset, wiring tightened');
    v_t1b := pg_temp.mk('c1', pg_temp.ctx('it_not_working')::integer, NULL, 'portal');
    PERFORM pg_temp.ok('a resolved ticket no longer blocks the customer: a new ticket is allowed (assumption 1)',
        (SELECT t.status FROM tickets t WHERE t.ticket_id = v_t1b) = 'open');
    PERFORM pg_temp.setctx('t1b', v_t1b);
    PERFORM pg_temp.fails('reopening while the customer has a newer active ticket names that ticket',
        format($q$CALL sp_change_ticket_status(1, %s, 'in_progress', NULL, %s, NULL)$q$, v_t, v_by), 'NX409', 'customerId',
        (SELECT ticket_no FROM tickets WHERE ticket_id = v_t1b));
    PERFORM pg_temp.ok('the refused reopen changed nothing',
        (SELECT status = 'resolved' FROM tickets WHERE ticket_id = v_t) AND (SELECT count(*) FROM ticket_status_history WHERE ticket_id = v_t) = 3);
    CALL sp_change_ticket_status(1, v_t1b, 'closed', 'Customer called: it fixed itself', v_by, NULL);
    PERFORM pg_temp.ok('open -> closed with a note works, and stamps closed_at only',
        (SELECT status = 'closed' AND closed_at IS NOT NULL AND resolved_at IS NULL FROM tickets WHERE ticket_id = v_t1b));
    CALL sp_change_ticket_status(1, v_t, 'in_progress', 'Not fixed after all', v_by, NULL);
    PERFORM pg_temp.ok('reopen from Resolved works and clears resolved_at',
        (SELECT status = 'in_progress' AND resolved_at IS NULL FROM tickets WHERE ticket_id = v_t));
    CALL sp_change_ticket_status(1, v_t, 'resolved', NULL, v_by, NULL);
    CALL sp_change_ticket_status(1, v_t, 'closed', NULL, v_by, NULL);
    PERFORM pg_temp.ok('resolved -> closed needs no note, stamps closed_at and keeps resolved_at',
        (SELECT status = 'closed' AND closed_at IS NOT NULL AND resolved_at IS NOT NULL FROM tickets WHERE ticket_id = v_t));
    PERFORM pg_temp.fails('closed is final: no reopen', format($q$CALL sp_change_ticket_status(1, %s, 'in_progress', 'again', %s, NULL)$q$, v_t, v_by), 'NX409', 'status');
    PERFORM pg_temp.fails('closed is final: no change at all', format($q$CALL sp_change_ticket_status(1, %s, 'closed', NULL, %s, NULL)$q$, v_t, v_by), 'NX409', 'status');
    PERFORM pg_temp.fails('closed is final: no assignment', format($q$CALL sp_assign_ticket(1, %s, %s, %s, NULL)$q$, v_t, v_by, v_by), 'NX409', 'status');
    v_t1b := pg_temp.mk('c1', pg_temp.ctx('it_not_working')::integer, NULL, 'portal');
    PERFORM pg_temp.ok('after closing, the customer can raise a new ticket',
        (SELECT ticket_no FROM tickets WHERE ticket_id = v_t1b) = pg_temp.no(7));   -- 0006 was the one closed with a note above
    PERFORM pg_temp.ok('the whole life of ticket 1 is in its history, oldest first',
        (SELECT string_agg(COALESCE(old_status, '-') || '>' || new_status, ' ' ORDER BY history_id) FROM fn_get_ticket_status_history(1, v_t, NULL))
        = '->open open>in_progress in_progress>resolved resolved>in_progress in_progress>resolved resolved>closed');
    PERFORM pg_temp.fails('internal ticket: open -> closed without a note', format($q$CALL sp_change_ticket_status(1, %s, 'closed', NULL, %s, NULL)$q$, pg_temp.ctx('t6'), v_by), '22023', 'note');
    PERFORM pg_temp.ok('... and it stayed open', (SELECT status FROM tickets WHERE ticket_id = pg_temp.ctx('t6')) = 'open');
END;
$$;

-- ---------------------------------------------------------------- assignment
DO $$
DECLARE
    v_t2 bigint := pg_temp.ctx('t2');
    v_t3 bigint := pg_temp.ctx('t3');
    v_by integer := pg_temp.ctx('admin');
    v_s1 integer := pg_temp.ctx('staff1');
    v_s2 integer := pg_temp.ctx('staff2');
BEGIN
    CALL sp_assign_ticket(1, v_t2, v_s1, v_by, NULL);
    PERFORM pg_temp.ok('assigning gives the ticket to the person and does NOT change its status',
        (SELECT assigned_to = v_s1 AND status = 'open' FROM tickets WHERE ticket_id = v_t2));
    PERFORM pg_temp.ok('assigning writes one history row: same status both sides, assigned_to set, who did it',
        (SELECT count(*) = 2 AND (array_agg(old_status ORDER BY history_id))[2] = 'open' AND (array_agg(new_status ORDER BY history_id))[2] = 'open'
                AND (array_agg(assigned_to ORDER BY history_id))[2] = v_s1 AND (array_agg(changed_by ORDER BY history_id))[2] = v_by
           FROM ticket_status_history WHERE ticket_id = v_t2));
    CALL sp_assign_ticket(1, v_t2, v_s1, v_by, NULL);
    PERFORM pg_temp.ok('assigning to the same person again writes nothing', (SELECT count(*) FROM ticket_status_history WHERE ticket_id = v_t2) = 2);
    PERFORM pg_temp.fails('a deactivated assignee', format($q$CALL sp_assign_ticket(1, %s, %s, %s, NULL)$q$, v_t2, pg_temp.ctx('gone'), v_by), 'NX409', 'assignedTo');
    PERFORM pg_temp.fails('an unknown assignee', format($q$CALL sp_assign_ticket(1, %s, 999999, %s, NULL)$q$, v_t2, v_by), 'P0002', 'assignedTo');
    PERFORM pg_temp.fails('an unknown ticket', format($q$CALL sp_assign_ticket(1, 999999, %s, %s, NULL)$q$, v_s1, v_by), 'P0002');
    CALL sp_assign_ticket(1, v_t3, v_by, v_by, NULL);
    PERFORM pg_temp.ok('an admin can be given a ticket too', (SELECT assigned_to = v_by FROM tickets WHERE ticket_id = v_t3));
    CALL sp_assign_ticket(1, v_t3, v_s2, v_by, NULL);
    PERFORM pg_temp.ok('the assignees list is every active user, staff and admin, and not the deactivated one',
        (SELECT count(*) FILTER (WHERE user_id IN (v_by, v_s1, v_s2)) = 3 AND count(*) FILTER (WHERE user_id = pg_temp.ctx('gone')) = 0 FROM fn_get_ticket_assignees(1)));
END;
$$;

-- ---------------------------------------------------------------- staff see only their own tickets
DO $$
DECLARE
    v_t2 bigint := pg_temp.ctx('t2');
    v_t3 bigint := pg_temp.ctx('t3');
    v_s1 integer := pg_temp.ctx('staff1');
    v_s2 integer := pg_temp.ctx('staff2');
    v_t7 bigint := pg_temp.mk('c7', pg_temp.ctx('it_inverter')::integer, NULL, 'portal');
BEGIN
    PERFORM pg_temp.setctx('t7', v_t7);
    PERFORM pg_temp.ok('a staff user''s list has only the tickets assigned to them (staff 1: just ticket 2)',
        (SELECT count(*) = 1 AND bool_and(ticket_id = v_t2) AND bool_and(total_count = 1) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, v_s1, 50, 0)));
    PERFORM pg_temp.ok('staff 2 has just ticket 3',
        (SELECT count(*) = 1 AND bool_and(ticket_id = v_t3) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, v_s2, 50, 0)));
    PERFORM pg_temp.ok('an admin (no visibility limit) sees all of the tickets',
        (SELECT count(*) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 50, 0)) = (SELECT count(*) FROM tickets WHERE tenant_id = 1));
    PERFORM pg_temp.ok('staff 1 cannot read ticket 3 (as if it did not exist)', NOT EXISTS (SELECT 1 FROM fn_get_ticket_by_id(1, v_t3, v_s1)));
    PERFORM pg_temp.ok('... nor its history', NOT EXISTS (SELECT 1 FROM fn_get_ticket_status_history(1, v_t3, v_s1)));
    PERFORM pg_temp.ok('... nor its files', NOT EXISTS (SELECT 1 FROM fn_get_ticket_attachments(1, v_t3, v_s1)));
    PERFORM pg_temp.ok('... nor download one', NOT EXISTS (SELECT 1 FROM fn_get_ticket_attachment(1, v_t3, pg_temp.ctx('att3'), v_s1)));
    PERFORM pg_temp.ok('staff 2 can read all of it', (SELECT count(*) FROM fn_get_ticket_by_id(1, v_t3, v_s2)) = 1
        AND (SELECT count(*) FROM fn_get_ticket_status_history(1, v_t3, v_s2)) >= 2 AND (SELECT count(*) FROM fn_get_ticket_attachment(1, v_t3, pg_temp.ctx('att3'), v_s2)) = 1);
    PERFORM pg_temp.ok('an unassigned ticket is visible to no staff user', NOT EXISTS (SELECT 1 FROM fn_get_ticket_by_id(1, v_t7, v_s1)));
    PERFORM pg_temp.fails('staff 1 cannot change ticket 3', format($q$CALL sp_change_ticket_status(1, %s, 'in_progress', NULL, %s, %s)$q$, v_t3, v_s1, v_s1), 'P0002');
    PERFORM pg_temp.fails('a staff user cannot assign a ticket that is not theirs', format($q$CALL sp_assign_ticket(1, %s, %s, %s, %s)$q$, v_t3, v_s1, v_s1, v_s1), '42501');
    CALL sp_change_ticket_status(1, v_t3, 'in_progress', NULL, v_s2, v_s2);
    PERFORM pg_temp.ok('staff 2 can change their own ticket', (SELECT status FROM tickets WHERE ticket_id = v_t3) = 'in_progress');
    PERFORM pg_temp.fails('a staff user cannot hand on even their OWN ticket (only administrators assign)', format($q$CALL sp_assign_ticket(1, %s, %s, %s, %s)$q$, v_t2, v_s2, v_s1, v_s1), '42501');
    PERFORM pg_temp.fails('... nor give it to themselves', format($q$CALL sp_assign_ticket(1, %s, %s, %s, %s)$q$, v_t2, v_s1, v_s1, v_s1), '42501');
    PERFORM pg_temp.ok('the refused assignment changed nothing: still with staff 1, and no new history row',
        (SELECT assigned_to = v_s1 FROM tickets WHERE ticket_id = v_t2) AND (SELECT count(*) FROM ticket_status_history WHERE ticket_id = v_t2) = 2);
END;
$$;

-- ---------------------------------------------------------------- the list: filters, search, paging
DO $$
DECLARE
    v_year  text := to_char(now(), 'YYYY');
    v_total bigint := (SELECT count(*) FROM tickets WHERE tenant_id = 1);
BEGIN
    PERFORM pg_temp.ok('status "active" is open and in progress together',
        (SELECT count(*) > 0 AND bool_and(status IN ('open', 'in_progress')) FROM fn_get_tickets(1, 'active', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 50, 0))
        AND (SELECT count(*) FROM fn_get_tickets(1, 'active', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 50, 0)) = (SELECT count(*) FROM tickets WHERE status IN ('open', 'in_progress')));
    PERFORM pg_temp.ok('status "closed" lists the closed ones',
        (SELECT count(*) > 0 AND bool_and(status = 'closed') FROM fn_get_tickets(1, 'closed', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 50, 0)));
    PERFORM pg_temp.ok('the source filter', (SELECT count(*) = 1 AND bool_and(ticket_id = pg_temp.ctx('t6')) FROM fn_get_tickets(1, NULL, NULL, NULL, 'internal', NULL, NULL, NULL, NULL, 50, 0)));
    PERFORM pg_temp.ok('the assignee filter', (SELECT count(*) = 1 FROM fn_get_tickets(1, NULL, pg_temp.ctx('staff2')::integer, NULL, NULL, NULL, NULL, NULL, NULL, 50, 0)));
    PERFORM pg_temp.ok('the customer filter', (SELECT count(*) = 3 FROM fn_get_tickets(1, NULL, NULL, pg_temp.ctx('c1'), NULL, NULL, NULL, NULL, NULL, 50, 0)));
    PERFORM pg_temp.ok('search by ticket number', (SELECT count(*) = 1 AND bool_and(ticket_id = pg_temp.ctx('t2')) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, pg_temp.no(2), NULL, NULL, NULL, 50, 0)));
    PERFORM pg_temp.ok('search by customer name, ignoring case', (SELECT count(*) = 1 AND bool_and(ticket_id = pg_temp.ctx('t2')) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, 'bINDU', NULL, NULL, NULL, 50, 0)));
    PERFORM pg_temp.ok('search by customer mobile', (SELECT count(*) = 1 AND bool_and(ticket_id = pg_temp.ctx('t3')) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, '9876500003', NULL, NULL, NULL, 50, 0)));
    PERFORM pg_temp.ok('search by issue text', (SELECT count(*) = 1 AND bool_and(ticket_id = pg_temp.ctx('t6')) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, 'strange NOISE', NULL, NULL, NULL, 50, 0)));
    PERFORM pg_temp.ok('a search with % is plain text, not a wildcard', (SELECT count(*) = 0 FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, '%', NULL, NULL, NULL, 50, 0)));
    PERFORM pg_temp.ok('tickets raised today are in a range that includes today',
        (SELECT count(*) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, NULL, current_date - 1, current_date + 1, NULL, 50, 0)) = v_total);
    PERFORM pg_temp.ok('a range that starts tomorrow is empty', (SELECT count(*) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, NULL, current_date + 1, NULL, NULL, 50, 0)) = 0);
    PERFORM pg_temp.ok('newest first', (SELECT (array_agg(ticket_id ORDER BY ordinality))[1] > (array_agg(ticket_id ORDER BY ordinality))[2]
        FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 50, 0) WITH ORDINALITY));
    PERFORM pg_temp.ok('paging: limit 2 gives two rows, each carrying the full total',
        (SELECT count(*) = 2 AND bool_and(total_count = v_total) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 2, 0)));
    PERFORM pg_temp.ok('paging: past the end gives no rows', (SELECT count(*) FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 2, 1000)) = 0);
    PERFORM pg_temp.fails('an unknown status filter', $q$SELECT ticket_id FROM fn_get_tickets(1, 'bogus', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 10, 0)$q$, '22023', 'status');
    PERFORM pg_temp.fails('an unknown source filter', $q$SELECT ticket_id FROM fn_get_tickets(1, NULL, NULL, NULL, 'sms', NULL, NULL, NULL, NULL, 10, 0)$q$, '22023', 'source');
END;
$$;

-- ---------------------------------------------------------------- the portal's Check Status
DO $$
DECLARE
    v_t2 bigint := pg_temp.ctx('t2');
BEGIN
    PERFORM pg_temp.ok('Check Status shows the open ticket: number, issue, status and the technician''s FIRST name only',
        (SELECT count(*) = 1 AND bool_and(issue_text = 'Inverter fault' AND status = 'open' AND technician_first_name = 'Ravi' AND ticket_no LIKE 'TKT-%')
           FROM fn_get_open_tickets_by_mobile(1, '9876500002')));
    PERFORM pg_temp.ok('an unassigned ticket has no technician name', (SELECT technician_first_name IS NULL FROM fn_get_open_tickets_by_mobile(1, '9876500007')));
    PERFORM pg_temp.ok('the function returns nothing but those five columns (no ids, no notes)',
        (SELECT pg_get_function_result(p.oid) FROM pg_proc p WHERE p.proname = 'fn_get_open_tickets_by_mobile')
        = 'TABLE(ticket_no character varying, issue_text character varying, status character varying, technician_first_name character varying, created_at timestamp with time zone)');
    PERFORM pg_temp.ok('an unknown mobile gives no rows', (SELECT count(*) FROM fn_get_open_tickets_by_mobile(1, '9000000000')) = 0);
    PERFORM pg_temp.ok('another tenant gets no rows for this mobile', (SELECT count(*) FROM fn_get_open_tickets_by_mobile(2, '9876500002')) = 0);
    UPDATE customers SET is_active = false WHERE customer_id = pg_temp.ctx('c3');
    PERFORM pg_temp.ok('a deactivated customer''s ticket is not shown', (SELECT count(*) FROM fn_get_open_tickets_by_mobile(1, '9876500003')) = 0);
    UPDATE customers SET is_active = true WHERE customer_id = pg_temp.ctx('c3');
    CALL sp_change_ticket_status(1, v_t2, 'in_progress', NULL, pg_temp.ctx('staff1')::integer, pg_temp.ctx('staff1')::integer);
    PERFORM pg_temp.ok('an in-progress ticket is still shown, with its new status', (SELECT status FROM fn_get_open_tickets_by_mobile(1, '9876500002')) = 'in_progress');
    CALL sp_change_ticket_status(1, v_t2, 'resolved', 'Done', pg_temp.ctx('staff1')::integer, pg_temp.ctx('staff1')::integer);
    PERFORM pg_temp.ok('a resolved ticket is hidden from Check Status', (SELECT count(*) FROM fn_get_open_tickets_by_mobile(1, '9876500002')) = 0);
    CALL sp_change_ticket_status(1, v_t2, 'closed', NULL, pg_temp.ctx('admin')::integer, NULL);
    PERFORM pg_temp.ok('a closed ticket is hidden too', (SELECT count(*) FROM fn_get_open_tickets_by_mobile(1, '9876500002')) = 0);
END;
$$;

-- ---------------------------------------------------------------- tenant isolation
DO $$
DECLARE
    v_t1 bigint := pg_temp.ctx('t1');
    v_ticket2 bigint;
BEGIN
    PERFORM pg_temp.ok('another tenant''s list is empty', (SELECT count(*) FROM fn_get_tickets(2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 50, 0)) = 0);
    PERFORM pg_temp.ok('another tenant cannot read a ticket', NOT EXISTS (SELECT 1 FROM fn_get_ticket_by_id(2, v_t1, NULL)));
    PERFORM pg_temp.ok('... its history', NOT EXISTS (SELECT 1 FROM fn_get_ticket_status_history(2, v_t1, NULL)));
    PERFORM pg_temp.ok('... its files', NOT EXISTS (SELECT 1 FROM fn_get_ticket_attachments(2, pg_temp.ctx('t3'), NULL))
        AND NOT EXISTS (SELECT 1 FROM fn_get_ticket_attachment(2, pg_temp.ctx('t3'), pg_temp.ctx('att3'), NULL)));
    PERFORM pg_temp.fails('another tenant cannot change a ticket', format($q$CALL sp_change_ticket_status(2, %s, 'in_progress', NULL, 1, NULL)$q$, v_t1), 'P0002');
    PERFORM pg_temp.fails('another tenant cannot assign a ticket', format($q$CALL sp_assign_ticket(2, %s, %s, 1, NULL)$q$, pg_temp.ctx('t7'), pg_temp.ctx('admin')), 'P0002');
    PERFORM pg_temp.fails('another tenant cannot attach a file', format($q$SELECT fn_add_ticket_attachment(2, %s, 'a.pdf', 'tenant2.pdf', 'application/pdf', 10)$q$, v_t1), 'P0002');
    SELECT c.ticket_id INTO v_ticket2 FROM fn_create_ticket(2, pg_temp.ctx('t2customer'), pg_temp.ctx('t2issue')::integer, NULL, 'Tenant two problem', 'portal', NULL, NULL, NULL, NULL, NULL) c;
    PERFORM pg_temp.ok('another tenant has its own number series, starting at 0001',
        (SELECT ticket_no FROM tickets WHERE ticket_id = v_ticket2) = 'TKT-' || to_char(now(), 'YYYY') || '-0001');   -- tenant 2 has its own series
    PERFORM pg_temp.ok('and tenant 1 still sees only its own tickets', NOT EXISTS (SELECT 1 FROM fn_get_tickets(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 100, 0) WHERE ticket_id = v_ticket2));
END;
$$;

-- ---------------------------------------------------------------- the history cannot be rewritten; the table rules
DO $$
BEGIN
    PERFORM pg_temp.fails('history rows cannot be updated', $q$UPDATE ticket_status_history SET note = 'edited'$q$, 'NX409');
    PERFORM pg_temp.fails('history rows cannot be deleted', $q$DELETE FROM ticket_status_history$q$, 'NX409');
    PERFORM pg_temp.fails('history cannot be truncated', $q$TRUNCATE ticket_status_history$q$, 'NX409');
    PERFORM pg_temp.fails('the database refuses a second active ticket for a customer, whatever the code does',
        format($q$INSERT INTO tickets (tenant_id, ticket_no, customer_id, issue_type_id, description, source)
                  VALUES (1, 'TKT-TEST-0001', %s, %s, 'd', 'portal')$q$, pg_temp.ctx('c7'), pg_temp.ctx('it_inverter')), '23505', NULL, NULL, 'uq_tickets_active_customer');
    PERFORM pg_temp.fails('a resolved ticket must have resolved_at', format($q$UPDATE tickets SET status = 'resolved' WHERE ticket_id = %s$q$, pg_temp.ctx('t7')), '23514', NULL, NULL, 'ck_tickets_stamps');
    PERFORM pg_temp.fails('a status outside the four', format($q$UPDATE tickets SET status = 'pending' WHERE ticket_id = %s$q$, pg_temp.ctx('t7')), '23514', NULL, NULL, 'ck_tickets_status');
    PERFORM pg_temp.fails('an assignment row must keep the status', format($q$INSERT INTO ticket_status_history (tenant_id, ticket_id, old_status, new_status, assigned_to)
                  VALUES (1, %s, 'open', 'closed', %s)$q$, pg_temp.ctx('t7'), pg_temp.ctx('admin')), '23514', NULL, NULL, 'ck_ticket_history_assignment');
    PERFORM pg_temp.fails('a ticket with both an issue type and free text', format($q$UPDATE tickets SET other_issue_text = 'x' WHERE ticket_id = %s$q$, pg_temp.ctx('t7')), '23514', NULL, NULL, 'ck_tickets_issue');
    PERFORM pg_temp.fails('a portal ticket with a creator', format($q$UPDATE tickets SET created_by = %s WHERE ticket_id = %s$q$, pg_temp.ctx('admin'), pg_temp.ctx('t7')), '23514', NULL, NULL, 'ck_tickets_creator');
    PERFORM pg_temp.fails('a description over 500 characters in the table itself', format($q$UPDATE tickets SET description = %L WHERE ticket_id = %s$q$, repeat('x', 501), pg_temp.ctx('t7')), '22001');
END;
$$;

SELECT count(*) || ' checks passed' AS result FROM t_pass;
ROLLBACK;
SELECT count(*) AS tickets_left_behind FROM tickets;
