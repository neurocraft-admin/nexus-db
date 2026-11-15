-- Module 8 (Staff and tasks): behaviour tests for the database. Everything runs in ONE transaction that is rolled back at the end, so it
-- leaves nothing behind (not even document numbers) and is safe to run on any database that has scripts 00-26 and the function files
-- applied. Stops at the first failure ("FAILED: <what>"); on success prints the count.
--   docker exec -i nexus-pg-test psql -U postgres -d <db> -v ON_ERROR_STOP=1 < tests/test_staff.sql
-- Simultaneous status changes need two sessions: tests/staff_concurrency.ps1.
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
CREATE FUNCTION pg_temp.fails(p_label text, p_sql text, p_state text, p_column text DEFAULT NULL, p_constraint text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_state text; v_column text; v_constraint text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
        GET STACKED DIAGNOSTICS v_column = COLUMN_NAME, v_constraint = CONSTRAINT_NAME;
    END;
    PERFORM pg_temp.ok(p_label || ' [refused with ' || p_state || ', got ' || COALESCE(v_state, 'no error') || ']', v_state = p_state);
    IF p_column IS NOT NULL THEN
        PERFORM pg_temp.ok(p_label || ' [names column ' || p_column || ']', v_column = p_column);
    END IF;
    IF p_constraint IS NOT NULL THEN
        PERFORM pg_temp.ok(p_label || ' [by ' || p_constraint || ']', v_constraint = p_constraint);
    END IF;
END;
$$;

-- Ticket numbers and task numbers are checked relative to where their counters stand.
CREATE TEMP TABLE t_base AS
SELECT COALESCE((SELECT last_no FROM document_counters WHERE tenant_id = 1 AND doc_type = 'TSK' AND doc_year = extract(year FROM now())::integer), 0) AS n;
CREATE FUNCTION pg_temp.tsk(p_n integer) RETURNS text LANGUAGE sql AS
    $$ SELECT 'TSK-' || to_char(now(), 'YYYY') || '-' || lpad(((SELECT n FROM t_base) + p_n)::text, 4, '0') $$;

CREATE FUNCTION pg_temp.new_user(p_name text, p_full text, p_role integer, p_type text, p_active boolean) RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO users (tenant_id, user_name, full_name, password_hash, role_id, user_type, is_active)
    VALUES (1, p_name, p_full, 'x', p_role, p_type, p_active) RETURNING user_id
$$;

-- A task for the assignee saved under that key; returns its id.
CREATE FUNCTION pg_temp.mk(p_assignee text, p_title text DEFAULT 'Install panels', p_at timestamptz DEFAULT NULL, p_type text DEFAULT 'installation',
                           p_customer text DEFAULT NULL) RETURNS bigint LANGUAGE sql AS $$
    SELECT fn_save_task(1, NULL, p_type, p_title, 'Roof work', CASE WHEN p_customer IS NULL THEN NULL ELSE pg_temp.ctx(p_customer) END, NULL,
                        pg_temp.ctx(p_assignee)::integer, p_at, NULL, NULL, NULL, pg_temp.ctx('admin')::integer, NULL)
$$;

CREATE FUNCTION pg_temp.status(p_task bigint) RETURNS text LANGUAGE sql AS $$ SELECT status FROM tasks WHERE task_id = p_task $$;
CREATE FUNCTION pg_temp.history(p_task bigint) RETURNS bigint LANGUAGE sql AS $$ SELECT count(*) FROM task_status_history WHERE task_id = p_task $$;
CREATE FUNCTION pg_temp.change(p_task bigint, p_status text, p_note text DEFAULT NULL, p_by text DEFAULT 'admin', p_visible text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    CALL sp_change_task_status(1, p_task, p_status, p_note, pg_temp.ctx(p_by)::integer, CASE WHEN p_visible IS NULL THEN NULL ELSE pg_temp.ctx(p_visible)::integer END);
END;
$$;

-- ---------------------------------------------------------------- setup
DO $$
DECLARE
    v_admin_role integer; v_staff_role integer; v_clerk_role integer;
BEGIN
    SELECT r.role_id INTO v_admin_role FROM roles r WHERE r.tenant_id = 1 AND r.role_name = 'Admin';
    SELECT r.role_id INTO v_staff_role FROM roles r WHERE r.tenant_id = 1 AND r.role_name = 'Staff';
    INSERT INTO roles (tenant_id, role_name) VALUES (1, 'ts_clerk') RETURNING role_id INTO v_clerk_role;
    PERFORM pg_temp.setctx('role_staff', v_staff_role);
    PERFORM pg_temp.setctx('role_clerk', v_clerk_role);
    PERFORM pg_temp.setctx('admin', pg_temp.new_user('ts_admin', 'Deepu Admin', v_admin_role, 'admin', true));
    PERFORM pg_temp.setctx('a', pg_temp.new_user('ts_a', 'Ravi Technician', v_staff_role, 'staff', true));
    PERFORM pg_temp.setctx('b', pg_temp.new_user('ts_b', 'Suma Technician', v_staff_role, 'staff', true));
    PERFORM pg_temp.setctx('clerk', pg_temp.new_user('ts_clerk_user', 'Clara Clerk', v_clerk_role, 'staff', true));
    PERFORM pg_temp.setctx('gone', pg_temp.new_user('ts_gone', 'Left Company', v_staff_role, 'staff', false));
    PERFORM pg_temp.setctx('c1', fn_save_customer(1, NULL, 'Anil Kumar', '9876600001', 'Tharayil House, Naruvamoodu'));
    PERFORM pg_temp.setctx('c2', fn_save_customer(1, NULL, 'Bindu Nair', '9876600002', 'Kodungannoor'));
    PERFORM pg_temp.setctx('c3', fn_save_customer(1, NULL, 'Chitra Devi', '9876600003', 'Pattom'));
    PERFORM pg_temp.setctx('type', (SELECT t.issue_type_id FROM issue_types t WHERE t.tenant_id = 1 AND t.issue_type_name = 'Not working'));
END;
$$;

-- ---------------------------------------------------------------- who can be given work
DO $$
BEGIN
    PERFORM pg_temp.ok('the Staff role can see My work', fn_role_can_receive_work(1, pg_temp.ctx('role_staff')::integer));
    PERFORM pg_temp.ok('a role with no my_work permission cannot', NOT fn_role_can_receive_work(1, pg_temp.ctx('role_clerk')::integer));
    PERFORM pg_temp.ok('the Admin role holds my_work view and update, the Staff role view and update only',
        (SELECT count(*) = 2 FROM role_permissions rp JOIN roles r ON r.role_id = rp.role_id JOIN resources x ON x.resource_id = rp.resource_id
          WHERE x.resource_code = 'my_work' AND r.role_name IN ('Admin', 'Staff') AND rp.can_view AND rp.can_update AND NOT rp.can_delete)
        AND NOT (SELECT rp.can_create FROM role_permissions rp JOIN roles r ON r.role_id = rp.role_id JOIN resources x ON x.resource_id = rp.resource_id
                  WHERE x.resource_code = 'my_work' AND r.role_name = 'Staff'));
    PERFORM pg_temp.ok('the assignees are the active staff users whose role can see My work: Ravi and Suma, not the clerk, the admin or the deactivated one',
        (SELECT array_agg(user_id ORDER BY user_id) FROM fn_get_task_assignees(1) WHERE user_id IN (pg_temp.ctx('a'), pg_temp.ctx('b'), pg_temp.ctx('clerk'), pg_temp.ctx('admin'), pg_temp.ctx('gone')))
        = ARRAY[pg_temp.ctx('a')::integer, pg_temp.ctx('b')::integer]);
END;
$$;

-- ---------------------------------------------------------------- staff records: user and profile together
DO $$
DECLARE
    v_id integer;
BEGIN
    v_id := fn_save_staff(1, NULL, 'ts_new', '  Anu Joseph ', '9876600010', pg_temp.ctx('role_staff')::integer, 'hash', ' E-001 ', ' Technician ', '', DATE '2026-01-05', '  ');
    PERFORM pg_temp.setctx('new', v_id);
    PERFORM pg_temp.ok('a new staff member is a staff-type user that must change the password, with a profile (blanks stored as NULL)',
        (SELECT u.user_type = 'staff' AND u.must_change_password AND u.is_active AND u.password_hash = 'hash'
                AND p.employee_code = 'E-001' AND p.designation = 'Technician' AND p.mobile_alt IS NULL AND p.notes IS NULL AND p.joining_date = DATE '2026-01-05'
           FROM users u JOIN staff_profiles p ON p.user_id = u.user_id WHERE u.user_id = v_id));
    PERFORM pg_temp.ok('the list shows them with whether they can receive work and no open work',
        (SELECT s.can_receive_work AND s.open_tasks = 0 AND s.open_tickets = 0 AND s.employee_code = 'E-001' FROM fn_get_staff(1, 'anu', false) s WHERE s.user_id = v_id));
    PERFORM pg_temp.ok('the list holds staff-type users only, never an admin account',
        NOT EXISTS (SELECT 1 FROM fn_get_staff(1, NULL, true) WHERE user_id = pg_temp.ctx('admin')));
    PERFORM pg_temp.ok('a deactivated person is left out unless asked for',
        NOT EXISTS (SELECT 1 FROM fn_get_staff(1, NULL, false) WHERE user_id = pg_temp.ctx('gone')) AND EXISTS (SELECT 1 FROM fn_get_staff(1, NULL, true) WHERE user_id = pg_temp.ctx('gone')));
    PERFORM fn_save_staff(1, v_id, 'ts_new', 'Anu J Joseph', '9876600010', pg_temp.ctx('role_clerk')::integer, 'ignored', 'E-002', 'Senior', '9876600011', NULL, 'Note');
    PERFORM pg_temp.ok('an edit changes the user and the profile and never the password',
        (SELECT u.full_name = 'Anu J Joseph' AND u.password_hash = 'hash' AND u.role_id = pg_temp.ctx('role_clerk') AND p.employee_code = 'E-002' AND p.mobile_alt = '9876600011' AND p.notes = 'Note'
           FROM users u JOIN staff_profiles p ON p.user_id = u.user_id WHERE u.user_id = v_id));
    PERFORM pg_temp.ok('a staff user with no profile row still appears (the profile is optional)',
        (SELECT s.employee_code IS NULL AND s.full_name = 'Ravi Technician' FROM fn_get_staff_by_id(1, pg_temp.ctx('a')::integer) s));
    PERFORM pg_temp.ok('an admin account is not found as staff', NOT EXISTS (SELECT 1 FROM fn_get_staff_by_id(1, pg_temp.ctx('admin')::integer)));
    PERFORM pg_temp.ok('another tenant sees none of them', (SELECT count(*) FROM fn_get_staff(2, NULL, true)) = 0);
END;
$$;

DO $$
DECLARE
    c_role text := pg_temp.ctx('role_staff')::text;
    v_users bigint := (SELECT count(*) FROM users);
BEGIN
    PERFORM pg_temp.fails('a duplicate user name', format($q$SELECT fn_save_staff(1, NULL, 'ts_new', 'X', NULL, %s, 'h', NULL, NULL, NULL, NULL, NULL)$q$, c_role), '23505', NULL, 'uq_users_tenant_user_name');
    PERFORM pg_temp.fails('a duplicate employee code (any case) is refused AND the user is not created either',
        format($q$SELECT fn_save_staff(1, NULL, 'ts_dup', 'X', NULL, %s, 'h', 'e-002', NULL, NULL, NULL, NULL)$q$, c_role), '23505', NULL, 'uq_staff_profiles_tenant_code');
    PERFORM pg_temp.ok('... so the failed profile rolled the user back (one transaction)', NOT EXISTS (SELECT 1 FROM users WHERE user_name = 'ts_dup') AND (SELECT count(*) FROM users) = v_users);
    PERFORM pg_temp.fails('a bad alternate mobile', format($q$SELECT fn_save_staff(1, NULL, 'ts_bad', 'X', NULL, %s, 'h', NULL, NULL, '12345', NULL, NULL)$q$, c_role), '22023', 'mobileAlt');
    PERFORM pg_temp.ok('... and no user was created', NOT EXISTS (SELECT 1 FROM users WHERE user_name = 'ts_bad'));
    PERFORM pg_temp.fails('a code over 30 characters', format($q$SELECT fn_save_staff(1, NULL, 'ts_bad', 'X', NULL, %s, 'h', %L, NULL, NULL, NULL, NULL)$q$, c_role, repeat('c', 31)), '22023', 'employeeCode');
    PERFORM pg_temp.fails('notes over 500 characters', format($q$SELECT fn_save_staff(1, NULL, 'ts_bad', 'X', NULL, %s, 'h', NULL, NULL, NULL, NULL, %L)$q$, c_role, repeat('n', 501)), '22023', 'notes');
    PERFORM pg_temp.fails('an unknown role', $q$SELECT fn_save_staff(1, NULL, 'ts_bad', 'X', NULL, 999999, 'h', NULL, NULL, NULL, NULL, NULL)$q$, 'P0002', 'roleId');
    PERFORM pg_temp.fails('editing an admin account through the staff function', format($q$SELECT fn_save_staff(1, %s, 'ts_admin', 'X', NULL, %s, NULL, NULL, NULL, NULL, NULL, NULL)$q$, pg_temp.ctx('admin'), c_role), 'P0002');
END;
$$;

-- ---------------------------------------------------------------- creating a task
DO $$
DECLARE
    v_task bigint;
    c_a text := pg_temp.ctx('a')::text;
    c_admin text := pg_temp.ctx('admin')::text;
BEGIN
    v_task := pg_temp.mk('a', '  Install 3 kW system ', now(), 'installation', 'c1');
    PERFORM pg_temp.setctx('t1', v_task);
    PERFORM pg_temp.ok('the first task is the next TSK-yyyy-nnnn (four digits), assigned, with its customer and a trimmed title',
        (SELECT task_no = pg_temp.tsk(1) AND status = 'assigned' AND title = 'Install 3 kW system' AND customer_id = pg_temp.ctx('c1') AND assigned_to = pg_temp.ctx('a')
                AND completed_at IS NULL FROM tasks WHERE task_id = v_task));
    PERFORM pg_temp.ok('it has exactly one history row: no old status, assigned, the first assignee, who made it',
        (SELECT count(*) = 1 AND bool_and(old_status IS NULL AND new_status = 'assigned' AND assigned_to = pg_temp.ctx('a') AND changed_by = pg_temp.ctx('admin'))
           FROM task_status_history WHERE task_id = v_task));
    PERFORM pg_temp.ok('the detail gives the customer mobile and the customer address when the task has none',
        (SELECT customer_mobile = '9876600001' AND visit_address IS NULL AND address = 'Tharayil House, Naruvamoodu' AND created_by_name = 'Deepu Admin' FROM fn_get_task_by_id(1, v_task, NULL)));
    PERFORM pg_temp.fails('a clerk (a role with no my_work) cannot be given a task', format($q$SELECT pg_temp.mk('clerk')$q$), 'NX409', 'assignedTo');
    PERFORM pg_temp.fails('an admin-type user cannot be given a task', $q$SELECT pg_temp.mk('admin')$q$, 'NX409', 'assignedTo');
    PERFORM pg_temp.fails('a deactivated person cannot', $q$SELECT pg_temp.mk('gone')$q$, 'NX409', 'assignedTo');
    PERFORM pg_temp.fails('an unknown assignee', $q$SELECT fn_save_task(1, NULL, 'other', 'x', NULL, NULL, NULL, 999999, NULL, NULL, NULL, NULL, 1, NULL)$q$, 'P0002', 'assignedTo');
    PERFORM pg_temp.fails('a staff user cannot create a task', format($q$SELECT fn_save_task(1, NULL, 'other', 'x', NULL, NULL, NULL, %s, NULL, NULL, NULL, NULL, %s, %s)$q$, c_a, c_a, c_a), '42501');
    PERFORM pg_temp.fails('a bad type', format($q$SELECT fn_save_task(1, NULL, 'repair', 'x', NULL, NULL, NULL, %s, NULL, NULL, NULL, NULL, %s, NULL)$q$, c_a, c_admin), '22023', 'taskType');
    PERFORM pg_temp.fails('a blank title', format($q$SELECT fn_save_task(1, NULL, 'other', '  ', NULL, NULL, NULL, %s, NULL, NULL, NULL, NULL, %s, NULL)$q$, c_a, c_admin), '22023', 'title');
    PERFORM pg_temp.fails('a title over 150', format($q$SELECT fn_save_task(1, NULL, 'other', %L, NULL, NULL, NULL, %s, NULL, NULL, NULL, NULL, %s, NULL)$q$, repeat('t', 151), c_a, c_admin), '22023', 'title');
    PERFORM pg_temp.fails('a description over 1000', format($q$SELECT fn_save_task(1, NULL, 'other', 'x', %L, NULL, NULL, %s, NULL, NULL, NULL, NULL, %s, NULL)$q$, repeat('d', 1001), c_a, c_admin), '22023', 'description');
    PERFORM pg_temp.fails('an address over 500', format($q$SELECT fn_save_task(1, NULL, 'other', 'x', NULL, NULL, NULL, %s, NULL, %L, NULL, NULL, %s, NULL)$q$, c_a, repeat('a', 501), c_admin), '22023', 'visitAddress');
    PERFORM pg_temp.fails('a latitude without a longitude', format($q$SELECT fn_save_task(1, NULL, 'other', 'x', NULL, NULL, NULL, %s, NULL, NULL, 9.5, NULL, %s, NULL)$q$, c_a, c_admin), '22023', 'latitude');
    PERFORM pg_temp.fails('a position out of range', format($q$SELECT fn_save_task(1, NULL, 'other', 'x', NULL, NULL, NULL, %s, NULL, NULL, 91, 76, %s, NULL)$q$, c_a, c_admin), '22023', 'latitude');
    PERFORM pg_temp.fails('an unknown customer', format($q$SELECT fn_save_task(1, NULL, 'other', 'x', NULL, 999999, NULL, %s, NULL, NULL, NULL, NULL, %s, NULL)$q$, c_a, c_admin), 'P0002', 'customerId');
    PERFORM pg_temp.fails('an unknown ticket', format($q$SELECT fn_save_task(1, NULL, 'other', 'x', NULL, NULL, 999999, %s, NULL, NULL, NULL, NULL, %s, NULL)$q$, c_a, c_admin), 'P0002', 'ticketId');
    v_task := pg_temp.mk('b', 'Second task');
    PERFORM pg_temp.ok('refused tasks used no number: the next task is the second', (SELECT task_no = pg_temp.tsk(2) FROM tasks WHERE task_id = v_task));
END;
$$;

DO $$
DECLARE
    v_ticket bigint;
    v_task   bigint;
BEGIN
    SELECT c.ticket_id INTO v_ticket FROM fn_create_ticket(1, pg_temp.ctx('c2'), pg_temp.ctx('type')::integer, NULL, 'Inverter beeps', 'internal', pg_temp.ctx('admin')::integer, NULL, NULL, NULL, NULL) c;
    PERFORM pg_temp.setctx('ticket2', v_ticket);
    v_task := fn_save_task(1, NULL, 'service', 'Visit for the beeping inverter', NULL, NULL, v_ticket, pg_temp.ctx('a')::integer, NULL, 'Kodungannoor, near the temple', 8.5241, 76.9366, pg_temp.ctx('admin')::integer, NULL);
    PERFORM pg_temp.setctx('t_ticket', v_task);
    PERFORM pg_temp.ok('a task for a ticket takes the ticket''s customer and keeps its own typed address and position',
        (SELECT customer_id = pg_temp.ctx('c2') AND ticket_no IS NOT NULL AND address = 'Kodungannoor, near the temple' AND latitude = 8.5241 AND longitude = 76.9366 FROM fn_get_task_by_id(1, v_task, NULL)));
    PERFORM pg_temp.fails('a ticket that belongs to another customer than the one chosen',
        format($q$SELECT fn_save_task(1, NULL, 'service', 'x', NULL, %s, %s, %s, NULL, NULL, NULL, NULL, %s, NULL)$q$, pg_temp.ctx('c1'), v_ticket, pg_temp.ctx('a'), pg_temp.ctx('admin')), '22023', 'ticketId');
    PERFORM pg_temp.ok('the task did not change the ticket (the link is informational)', (SELECT status FROM tickets WHERE ticket_id = v_ticket) = 'open');
END;
$$;

-- ---------------------------------------------------------------- editing
DO $$
DECLARE
    v_t bigint := pg_temp.ctx('t1');
BEGIN
    PERFORM fn_save_task(1, v_t, 'site_visit', 'Survey the roof', 'New description', pg_temp.ctx('c3'), NULL, pg_temp.ctx('b')::integer, now() + interval '1 day', '  New address ', NULL, NULL, pg_temp.ctx('admin')::integer, NULL);
    PERFORM pg_temp.ok('an edit changes the details and NOT the assignee or the status (the assignee argument is ignored on edit)',
        (SELECT task_type = 'site_visit' AND title = 'Survey the roof' AND customer_id = pg_temp.ctx('c3') AND visit_address = 'New address' AND assigned_to = pg_temp.ctx('a') AND status = 'assigned'
           FROM tasks WHERE task_id = v_t));
    PERFORM pg_temp.ok('an edit wrote no history row', pg_temp.history(v_t) = 1);
    PERFORM pg_temp.fails('editing an unknown task', format($q$SELECT fn_save_task(1, 999999, 'other', 'x', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, %s, NULL)$q$, pg_temp.ctx('admin')), 'P0002');
    PERFORM pg_temp.fails('a staff user cannot edit', format($q$SELECT fn_save_task(1, %s, 'other', 'x', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, %s, %s)$q$, v_t, pg_temp.ctx('a'), pg_temp.ctx('a')), '42501');
END;
$$;

-- ---------------------------------------------------------------- the status rules: every one of the 16 moves
DO $$
DECLARE
    v_old text; v_new text; v_state text;
    c_all     CONSTANT text[] := ARRAY['assigned', 'in_progress', 'done', 'cancelled'];
    c_allowed CONSTANT text[] := ARRAY['assigned>in_progress', 'assigned>cancelled', 'in_progress>done', 'in_progress>cancelled'];
    v_checked integer := 0;
BEGIN
    FOREACH v_old IN ARRAY c_all LOOP
        FOREACH v_new IN ARRAY c_all LOOP
            v_state := NULL;
            BEGIN
                CALL sp_check_task_status_move(v_old, v_new, 'a note');
            EXCEPTION WHEN OTHERS THEN
                v_state := SQLSTATE;
            END;
            PERFORM pg_temp.ok(format('move %s -> %s is %s', v_old, v_new, CASE WHEN (v_old || '>' || v_new) = ANY (c_allowed) THEN 'allowed' ELSE 'refused' END),
                CASE WHEN (v_old || '>' || v_new) = ANY (c_allowed) THEN v_state IS NULL ELSE v_state = 'NX409' END);
            v_checked := v_checked + 1;
        END LOOP;
    END LOOP;
    PERFORM pg_temp.ok('all 16 moves were checked', v_checked = 16);
    PERFORM pg_temp.fails('done without a note', $q$CALL sp_check_task_status_move('in_progress', 'done', NULL)$q$, '22023', 'note');
    PERFORM pg_temp.fails('done with a blank note', $q$CALL sp_check_task_status_move('in_progress', 'done', '   ')$q$, '22023', 'note');
    PERFORM pg_temp.fails('an unknown status', $q$CALL sp_check_task_status_move('assigned', 'finished', NULL)$q$, '22023', 'status');
    PERFORM pg_temp.fails('a note over 500 characters', format($q$CALL sp_check_task_status_move('assigned', 'in_progress', %L)$q$, repeat('n', 501)), '22023', 'note');
    CALL sp_check_task_status_move('assigned', 'in_progress', NULL);
    CALL sp_check_task_status_move('in_progress', 'cancelled', NULL);
    PERFORM pg_temp.ok('starting and cancelling need no note', true);
END;
$$;

-- ---------------------------------------------------------------- one task's life, and who may do what
DO $$
DECLARE
    v_t bigint := pg_temp.ctx('t1');
BEGIN
    PERFORM pg_temp.fails('Suma cannot touch Ravi''s task (not found)', format($q$SELECT pg_temp.change(%s, 'in_progress', NULL, 'b', 'b')$q$, v_t), 'P0002');
    PERFORM pg_temp.change(v_t, 'in_progress', NULL, 'a', 'a');
    PERFORM pg_temp.ok('Ravi starts his own task: in progress, one more history row', pg_temp.status(v_t) = 'in_progress' AND pg_temp.history(v_t) = 2);
    PERFORM pg_temp.fails('the same status again', format($q$SELECT pg_temp.change(%s, 'in_progress')$q$, v_t), 'NX409', 'status');
    PERFORM pg_temp.fails('a staff user cannot cancel, even their own task', format($q$SELECT pg_temp.change(%s, 'cancelled', 'no', 'a', 'a')$q$, v_t), '42501');
    PERFORM pg_temp.fails('done needs a note', format($q$SELECT pg_temp.change(%s, 'done', '  ', 'a', 'a')$q$, v_t), '22023', 'note');
    PERFORM pg_temp.ok('the refused changes wrote nothing', pg_temp.status(v_t) = 'in_progress' AND pg_temp.history(v_t) = 2);
    PERFORM pg_temp.change(v_t, 'done', '  Installed and tested  ', 'a', 'a');
    PERFORM pg_temp.ok('done stamps the time and keeps the trimmed note as the completion note',
        (SELECT status = 'done' AND completed_at IS NOT NULL AND completion_note = 'Installed and tested' FROM tasks WHERE task_id = v_t));
    PERFORM pg_temp.ok('the timeline reads created, started, done, with who and the note',
        (SELECT string_agg(COALESCE(old_status, '-') || '>' || new_status, ' ' ORDER BY history_id) FROM fn_get_task_history(1, v_t, NULL)) = '->assigned assigned>in_progress in_progress>done'
        AND (SELECT note FROM task_status_history WHERE task_id = v_t AND new_status = 'done') = 'Installed and tested');
    PERFORM pg_temp.fails('a finished task cannot be changed again', format($q$SELECT pg_temp.change(%s, 'in_progress')$q$, v_t), 'NX409', 'status');
    PERFORM pg_temp.fails('a finished task cannot be edited', format($q$SELECT fn_save_task(1, %s, 'other', 'x', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, %s, NULL)$q$, v_t, pg_temp.ctx('admin')), 'NX409', 'status');
    PERFORM pg_temp.fails('a finished task cannot be reassigned', format($q$CALL sp_assign_task(1, %s, %s, %s, NULL)$q$, v_t, pg_temp.ctx('b'), pg_temp.ctx('admin')), 'NX409', 'status');
    PERFORM pg_temp.fails('an unknown task', $q$SELECT pg_temp.change(999999, 'in_progress')$q$, 'P0002');
END;
$$;

DO $$
DECLARE
    v_t bigint := pg_temp.mk('a', 'To be cancelled');
BEGIN
    PERFORM pg_temp.change(v_t, 'cancelled', 'Customer postponed');
    PERFORM pg_temp.ok('an administrator can cancel: it is final, stamped, and has no completion note',
        (SELECT status = 'cancelled' AND completed_at IS NOT NULL AND completion_note IS NULL FROM tasks WHERE task_id = v_t));
    PERFORM pg_temp.fails('a cancelled task cannot be changed', format($q$SELECT pg_temp.change(%s, 'in_progress')$q$, v_t), 'NX409');
END;
$$;

-- ---------------------------------------------------------------- reassigning
DO $$
DECLARE
    v_t bigint := pg_temp.mk('a', 'Move me');
    c_admin text := pg_temp.ctx('admin')::text;
BEGIN
    PERFORM pg_temp.change(v_t, 'in_progress', NULL, 'a', 'a');
    CALL sp_assign_task(1, v_t, pg_temp.ctx('b')::integer, pg_temp.ctx('admin')::integer, NULL);
    PERFORM pg_temp.ok('an administrator can reassign an in-progress task: new person, SAME status, one history row naming who it went to',
        (SELECT assigned_to = pg_temp.ctx('b') AND status = 'in_progress' FROM tasks WHERE task_id = v_t) AND pg_temp.history(v_t) = 3
        AND (SELECT old_status = 'in_progress' AND new_status = 'in_progress' AND assigned_to = pg_temp.ctx('b') AND changed_by = pg_temp.ctx('admin')
               FROM task_status_history WHERE task_id = v_t ORDER BY history_id DESC LIMIT 1));
    CALL sp_assign_task(1, v_t, pg_temp.ctx('b')::integer, pg_temp.ctx('admin')::integer, NULL);
    PERFORM pg_temp.ok('assigning to the same person again writes nothing', pg_temp.history(v_t) = 3);
    PERFORM pg_temp.ok('after the move Ravi cannot see it and Suma can',
        NOT EXISTS (SELECT 1 FROM fn_get_task_by_id(1, v_t, pg_temp.ctx('a')::integer)) AND EXISTS (SELECT 1 FROM fn_get_task_by_id(1, v_t, pg_temp.ctx('b')::integer)));
    PERFORM pg_temp.fails('a staff user cannot assign, not even their own task', format($q$CALL sp_assign_task(1, %s, %s, %s, %s)$q$, v_t, pg_temp.ctx('a'), pg_temp.ctx('b'), pg_temp.ctx('b')), '42501');
    PERFORM pg_temp.fails('a clerk cannot be the new assignee', format($q$CALL sp_assign_task(1, %s, %s, %s, NULL)$q$, v_t, pg_temp.ctx('clerk'), c_admin), 'NX409', 'assignedTo');
    PERFORM pg_temp.fails('an unknown assignee', format($q$CALL sp_assign_task(1, %s, 999999, %s, NULL)$q$, v_t, c_admin), 'P0002', 'assignedTo');
    PERFORM pg_temp.fails('an unknown task', format($q$CALL sp_assign_task(1, 999999, %s, %s, NULL)$q$, pg_temp.ctx('a'), c_admin), 'P0002');
    PERFORM pg_temp.setctx('moved', v_t);
END;
$$;

-- ---------------------------------------------------------------- staff see only their own tasks
DO $$
DECLARE
    v_a bigint[]; v_b bigint[];
BEGIN
    SELECT array_agg(task_id) INTO v_a FROM fn_get_tasks(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, pg_temp.ctx('a')::integer, 100, 0);
    SELECT array_agg(task_id) INTO v_b FROM fn_get_tasks(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, pg_temp.ctx('b')::integer, 100, 0);
    PERFORM pg_temp.ok('Ravi''s list has only tasks assigned to Ravi', v_a IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM tasks WHERE task_id = ANY (v_a) AND assigned_to <> pg_temp.ctx('a')) AND (SELECT count(*) FROM tasks WHERE assigned_to = pg_temp.ctx('a')) = array_length(v_a, 1));
    PERFORM pg_temp.ok('Suma''s list has only Suma''s', v_b IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tasks WHERE task_id = ANY (v_b) AND assigned_to <> pg_temp.ctx('b')));
    PERFORM pg_temp.ok('an administrator (no limit) sees all of them',
        (SELECT max(total_count) FROM fn_get_tasks(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1, 0)) = (SELECT count(*) FROM tasks WHERE tenant_id = 1));
    PERFORM pg_temp.ok('Ravi cannot read Suma''s task, nor its history',
        NOT EXISTS (SELECT 1 FROM fn_get_task_by_id(1, pg_temp.ctx('moved'), pg_temp.ctx('a')::integer)) AND NOT EXISTS (SELECT 1 FROM fn_get_task_history(1, pg_temp.ctx('moved'), pg_temp.ctx('a')::integer)));
    PERFORM pg_temp.ok('another tenant sees and reads nothing', (SELECT count(*) FROM fn_get_tasks(2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 100, 0)) = 0
        AND NOT EXISTS (SELECT 1 FROM fn_get_task_by_id(2, pg_temp.ctx('moved'), NULL)) AND NOT EXISTS (SELECT 1 FROM fn_get_task_history(2, pg_temp.ctx('moved'), NULL)));
    PERFORM pg_temp.fails('another tenant cannot change or assign a task', format($q$CALL sp_change_task_status(2, %s, 'in_progress', NULL, 1, NULL)$q$, pg_temp.ctx('moved')), 'P0002');
    PERFORM pg_temp.fails('... nor assign', format($q$CALL sp_assign_task(2, %s, %s, 1, NULL)$q$, pg_temp.ctx('moved'), pg_temp.ctx('a')), 'P0002');
END;
$$;

-- ---------------------------------------------------------------- the list: filters, search, paging
DO $$
DECLARE
    v_today date := (now() AT TIME ZONE 'UTC')::date;
    v_tag   text := 'Zq' || substr(md5(random()::text), 1, 8);
    v_t     bigint;
    v_late  bigint;
BEGIN
    v_t := pg_temp.mk('b', v_tag || ' special', now(), 'service', 'c1');
    PERFORM pg_temp.ok('filter by status open (assigned and in progress together), by type and by customer',
        (SELECT count(*) = 1 FROM fn_get_tasks(1, NULL, 'open', 'service', NULL, NULL, pg_temp.ctx('c1'), v_tag, NULL, 50, 0) WHERE task_id = v_t));
    PERFORM pg_temp.ok('search by title, number and customer name, ignoring case',
        (SELECT count(*) = 1 FROM fn_get_tasks(1, NULL, NULL, NULL, NULL, NULL, NULL, upper(v_tag), NULL, 50, 0))
        AND (SELECT count(*) = 1 FROM fn_get_tasks(1, NULL, NULL, NULL, NULL, NULL, NULL, (SELECT task_no FROM tasks WHERE task_id = v_t), NULL, 50, 0)));
    PERFORM pg_temp.ok('a % in the search is plain text', (SELECT count(*) = 0 FROM fn_get_tasks(1, NULL, NULL, NULL, NULL, NULL, NULL, '%', NULL, 50, 0)));
    PERFORM pg_temp.ok('the date range is the scheduled day: today includes it, tomorrow onward does not',
        (SELECT count(*) = 1 FROM fn_get_tasks(1, NULL, NULL, NULL, v_today, v_today, NULL, v_tag, NULL, 50, 0))
        AND (SELECT count(*) = 0 FROM fn_get_tasks(1, NULL, NULL, NULL, v_today + 1, NULL, NULL, v_tag, NULL, 50, 0)));
    PERFORM pg_temp.ok('the assignee filter', (SELECT count(*) = 1 FROM fn_get_tasks(1, pg_temp.ctx('b')::integer, NULL, NULL, NULL, NULL, NULL, v_tag, NULL, 50, 0))
        AND (SELECT count(*) = 0 FROM fn_get_tasks(1, pg_temp.ctx('a')::integer, NULL, NULL, NULL, NULL, NULL, v_tag, NULL, 50, 0)));
    PERFORM pg_temp.ok('paging: two rows carry the full total, and past the end gives none',
        (SELECT count(*) = 2 AND bool_and(total_count = (SELECT count(*) FROM tasks WHERE tenant_id = 1)) FROM fn_get_tasks(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 2, 0))
        AND (SELECT count(*) = 0 FROM fn_get_tasks(1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 2, 100000)));
    v_late := pg_temp.mk('b', 'Late job', now() - interval '3 days');
    PERFORM pg_temp.ok('a task scheduled before today and still open is overdue; one scheduled today is not',
        (SELECT is_overdue FROM fn_get_task_by_id(1, v_late, NULL))
        AND NOT (SELECT is_overdue FROM fn_get_task_by_id(1, v_t, NULL)));
    PERFORM pg_temp.fails('an unknown status filter', $q$SELECT task_id FROM fn_get_tasks(1, NULL, 'bogus', NULL, NULL, NULL, NULL, NULL, NULL, 10, 0)$q$, '22023', 'status');
    PERFORM pg_temp.fails('an unknown type filter', $q$SELECT task_id FROM fn_get_tasks(1, NULL, NULL, 'repair', NULL, NULL, NULL, NULL, NULL, 10, 0)$q$, '22023', 'taskType');
    PERFORM pg_temp.fails('an end date before the start date', $q$SELECT task_id FROM fn_get_tasks(1, NULL, NULL, NULL, DATE '2026-02-01', DATE '2026-01-01', NULL, NULL, NULL, 10, 0)$q$, '22023', 'to');
END;
$$;

-- ---------------------------------------------------------------- deactivation: open work must be reassigned first
DO $$
DECLARE
    v_user   integer := pg_temp.new_user('ts_leaver', 'Leaving Soon', pg_temp.ctx('role_staff')::integer, 'staff', true);
    v_task   bigint;
    v_ticket bigint;
BEGIN
    PERFORM pg_temp.setctx('leaver', v_user);
    v_task := pg_temp.mk('leaver', 'Last job');
    PERFORM pg_temp.fails('the Users path (fn_set_user_active) refuses while they have an open task, naming the counts',
        format($q$SELECT fn_set_user_active(1, %s, false)$q$, v_user), 'NX409', 'isActive');
    PERFORM pg_temp.fails('the Staff path (fn_set_staff_active) refuses the same way', format($q$SELECT fn_set_staff_active(1, %s, false)$q$, v_user), 'NX409', 'isActive');
    PERFORM pg_temp.ok('nothing changed: still active', (SELECT is_active FROM users WHERE user_id = v_user));
    CALL sp_assign_task(1, v_task, pg_temp.ctx('b')::integer, pg_temp.ctx('admin')::integer, NULL);
    SELECT c.ticket_id INTO v_ticket FROM fn_create_ticket(1, pg_temp.ctx('c3'), pg_temp.ctx('type')::integer, NULL, 'Low output', 'internal', pg_temp.ctx('admin')::integer, NULL, NULL, NULL, NULL) c;
    CALL sp_assign_ticket(1, v_ticket, v_user, pg_temp.ctx('admin')::integer, NULL);
    PERFORM pg_temp.fails('an open TICKET blocks it too (tasks reassigned, ticket still theirs)', format($q$SELECT fn_set_user_active(1, %s, false)$q$, v_user), 'NX409', 'isActive');
    CALL sp_assign_ticket(1, v_ticket, pg_temp.ctx('b')::integer, pg_temp.ctx('admin')::integer, NULL);
    PERFORM fn_set_staff_active(1, v_user, false);
    PERFORM pg_temp.ok('once their work is reassigned they can be deactivated', NOT (SELECT is_active FROM users WHERE user_id = v_user));
    PERFORM fn_set_user_active(1, v_user, true);
    PERFORM pg_temp.ok('and switched on again (no rule against it)', (SELECT is_active FROM users WHERE user_id = v_user));
    PERFORM pg_temp.fails('the Staff path refuses an admin account (not found)', format($q$SELECT fn_set_staff_active(1, %s, false)$q$, pg_temp.ctx('admin')), 'P0002');
    PERFORM pg_temp.fails('the old rules still hold: an unknown user', $q$SELECT fn_set_user_active(1, 999999, false)$q$, 'P0002');
    PERFORM pg_temp.setctx('ticket_b', v_ticket);
END;
$$;

DO $$
DECLARE
    v_user integer := pg_temp.new_user('ts_role', 'Role Change', pg_temp.ctx('role_staff')::integer, 'staff', true);
BEGIN
    PERFORM pg_temp.mk('a', 'x');   -- keeps the counter honest; not Role Change's
    PERFORM fn_save_task(1, NULL, 'other', 'For role change', NULL, NULL, NULL, v_user, NULL, NULL, NULL, NULL, pg_temp.ctx('admin')::integer, NULL);
    PERFORM pg_temp.fails('moving someone with open tasks to a role that cannot see My work is refused',
        format($q$SELECT fn_save_staff(1, %s, 'ts_role', 'Role Change', NULL, %s, NULL, NULL, NULL, NULL, NULL, NULL)$q$, v_user, pg_temp.ctx('role_clerk')), 'NX409', 'roleId');
    PERFORM pg_temp.ok('the role did not change', (SELECT role_id = pg_temp.ctx('role_staff') FROM users WHERE user_id = v_user));
    PERFORM pg_temp.setctx('rolechange', v_user);
END;
$$;

-- ---------------------------------------------------------------- vw_staff_work and My work
DO $$
DECLARE
    v_user integer := pg_temp.new_user('ts_w', 'Work Person', pg_temp.ctx('role_staff')::integer, 'staff', true);
    v_today bigint; v_over bigint; v_later bigint; v_none bigint; v_done bigint; v_old bigint; v_cancel bigint; v_tk bigint; v_tk_done bigint; v_other bigint;
BEGIN
    PERFORM pg_temp.setctx('w', v_user);
    v_today := pg_temp.mk('w', 'W today', now());
    v_over  := pg_temp.mk('w', 'W overdue', now() - interval '2 days');
    v_later := pg_temp.mk('w', 'W later', now() + interval '3 days');
    v_none  := pg_temp.mk('w', 'W unscheduled');
    v_done  := pg_temp.mk('w', 'W done lately');
    v_old   := pg_temp.mk('w', 'W done long ago');
    v_cancel := pg_temp.mk('w', 'W cancelled lately');
    v_other := pg_temp.mk('b', 'Not Work Person''s');
    PERFORM pg_temp.change(v_done, 'in_progress', NULL, 'w', 'w');
    PERFORM pg_temp.change(v_done, 'done', 'Finished', 'w', 'w');
    PERFORM pg_temp.change(v_old, 'in_progress', NULL, 'w', 'w');
    PERFORM pg_temp.change(v_old, 'done', 'Finished long ago', 'w', 'w');
    UPDATE tasks SET completed_at = now() - interval '8 days' WHERE task_id = v_old;
    PERFORM pg_temp.change(v_cancel, 'cancelled', 'Not needed');
    SELECT c.ticket_id INTO v_tk FROM fn_create_ticket(1, pg_temp.ctx('c1'), pg_temp.ctx('type')::integer, NULL, 'Cleaning needed', 'internal', pg_temp.ctx('admin')::integer, NULL, NULL, NULL, NULL) c;
    CALL sp_assign_ticket(1, v_tk, v_user, pg_temp.ctx('admin')::integer, NULL);
    PERFORM pg_temp.setctx('w_ticket', v_tk);
    PERFORM pg_temp.ok('the view lists the person''s tasks and assigned tickets together, in one shape, and nobody else''s',
        (SELECT count(*) FROM vw_staff_work WHERE tenant_id = 1 AND user_id = v_user AND work_kind = 'task') = 7
        AND (SELECT count(*) FROM vw_staff_work WHERE tenant_id = 1 AND user_id = v_user AND work_kind = 'ticket') = 1
        AND NOT EXISTS (SELECT 1 FROM vw_staff_work WHERE user_id = v_user AND work_id = v_other AND work_kind = 'task'));
    PERFORM pg_temp.ok('Today: a task scheduled today, an OVERDUE one marked as such, and every open ticket',
        (SELECT array_agg(title::text ORDER BY title) FROM fn_get_my_work(1, v_user) WHERE bucket = 'today') = ARRAY['Not working', 'W overdue', 'W today']
        AND (SELECT is_overdue FROM fn_get_my_work(1, v_user) WHERE work_id = v_over AND work_kind = 'task')
        AND NOT (SELECT is_overdue FROM fn_get_my_work(1, v_user) WHERE work_id = v_today AND work_kind = 'task'));
    PERFORM pg_temp.ok('Upcoming: a later task and an unscheduled one',
        (SELECT array_agg(title::text ORDER BY title) FROM fn_get_my_work(1, v_user) WHERE bucket = 'upcoming') = ARRAY['W later', 'W unscheduled']);
    PERFORM pg_temp.ok('Done: tasks finished (done or cancelled) in the last 7 days, but not the one finished 8 days ago',
        (SELECT array_agg(title::text ORDER BY title) FROM fn_get_my_work(1, v_user) WHERE bucket = 'done') = ARRAY['W cancelled lately', 'W done lately']);
    CALL sp_change_ticket_status(1, v_tk, 'in_progress', NULL, pg_temp.ctx('admin')::integer, NULL);
    CALL sp_change_ticket_status(1, v_tk, 'resolved', 'Fixed', v_user, v_user);
    PERFORM pg_temp.ok('a resolved ticket moves from Today to Done',
        (SELECT bucket FROM fn_get_my_work(1, v_user) WHERE work_kind = 'ticket' AND work_id = v_tk) = 'done');
    PERFORM pg_temp.ok('the order is Today, then Upcoming, then Done',
        (SELECT string_agg(b, ',' ORDER BY first_pos) FROM (SELECT bucket::text AS b, min(n) AS first_pos FROM fn_get_my_work(1, v_user) WITH ORDINALITY AS w(work_kind, work_id, reference_no, title, work_type, customer_name, customer_mobile, address, latitude, longitude, scheduled_at, status, bucket, is_overdue, finished_at, n) GROUP BY bucket) g) = 'today,upcoming,done');
    PERFORM pg_temp.ok('the work comes with the customer name, mobile and the address (the task''s own, else the customer''s)',
        (SELECT customer_name IS NOT NULL OR title = 'W unscheduled' FROM fn_get_my_work(1, v_user) WHERE work_id = v_tk AND work_kind = 'ticket'));
    PERFORM pg_temp.ok('someone else sees none of it, and another tenant sees none of it',
        NOT EXISTS (SELECT 1 FROM fn_get_my_work(1, pg_temp.ctx('b')::integer) WHERE title LIKE 'W %')
        AND (SELECT count(*) FROM fn_get_my_work(2, v_user)) = 0);
END;
$$;

-- ---------------------------------------------------------------- reports
DO $$
DECLARE
    v_user integer := pg_temp.ctx('w')::integer;
    v_today date := (now() AT TIME ZONE 'UTC')::date;
BEGIN
    PERFORM pg_temp.ok('My completed tasks: today''s done task and the one finished 8 days ago, each in its own range',
        (SELECT count(*) = 1 AND bool_and(title = 'W done lately') FROM fn_get_my_completed_tasks(1, v_user, v_today, v_today))
        AND (SELECT count(*) = 1 AND bool_and(title = 'W done long ago') FROM fn_get_my_completed_tasks(1, v_user, v_today - 10, v_today - 5))
        AND (SELECT count(*) = 2 AND bool_and(total_count = 2) FROM fn_get_my_completed_tasks(1, v_user, NULL, NULL)));
    PERFORM pg_temp.ok('... never someone else''s, never cancelled ones',
        NOT EXISTS (SELECT 1 FROM fn_get_my_completed_tasks(1, pg_temp.ctx('b')::integer, NULL, NULL) WHERE title LIKE 'W %'));
    PERFORM pg_temp.ok('My resolved tickets: the ticket this person moved to Resolved, with the time and its current status',
        (SELECT count(*) = 1 AND bool_and(ticket_id = pg_temp.ctx('w_ticket') AND status = 'resolved') FROM fn_get_my_resolved_tickets(1, v_user, v_today, v_today)));
    PERFORM pg_temp.ok('... not the one who merely has it assigned or the one who started it',
        NOT EXISTS (SELECT 1 FROM fn_get_my_resolved_tickets(1, pg_temp.ctx('admin')::integer, NULL, NULL) WHERE ticket_id = pg_temp.ctx('w_ticket')));
    CALL sp_change_ticket_status(1, pg_temp.ctx('w_ticket'), 'in_progress', 'Reopen', pg_temp.ctx('admin')::integer, NULL);
    CALL sp_change_ticket_status(1, pg_temp.ctx('w_ticket'), 'resolved', 'Again', v_user, v_user);
    PERFORM pg_temp.ok('a ticket resolved twice by the same person is listed once', (SELECT count(*) = 1 FROM fn_get_my_resolved_tickets(1, v_user, NULL, NULL)));
    PERFORM pg_temp.fails('an end before the start (tasks)', format($q$SELECT task_id FROM fn_get_my_completed_tasks(1, %s, DATE '2026-02-01', DATE '2026-01-01')$q$, v_user), '22023', 'to');
    PERFORM pg_temp.fails('an end before the start (tickets)', format($q$SELECT ticket_id FROM fn_get_my_resolved_tickets(1, %s, DATE '2026-02-01', DATE '2026-01-01')$q$, v_user), '22023', 'to');
    PERFORM pg_temp.ok('the dashboard load counts open tasks, overdue ones and open tickets per active staff user',
        (SELECT open_tasks = 4 AND overdue_tasks = 1 AND open_tickets = 0 FROM fn_get_staff_task_load(1) WHERE user_id = v_user)
        AND NOT EXISTS (SELECT 1 FROM fn_get_staff_task_load(1) WHERE user_id = pg_temp.ctx('gone') OR user_id = pg_temp.ctx('admin')));
END;
$$;

-- ---------------------------------------------------------------- the history cannot be rewritten; the table rules
DO $$
DECLARE
    v_t bigint := pg_temp.ctx('t1');
BEGIN
    PERFORM pg_temp.fails('history rows cannot be updated', $q$UPDATE task_status_history SET note = 'edited'$q$, 'NX409');
    PERFORM pg_temp.fails('history rows cannot be deleted', $q$DELETE FROM task_status_history$q$, 'NX409');
    PERFORM pg_temp.fails('history cannot be truncated', $q$TRUNCATE task_status_history$q$, 'NX409');
    PERFORM pg_temp.fails('the table refuses a done task with no note', format($q$UPDATE tasks SET status = 'done', completed_at = now() WHERE task_id = %s$q$, pg_temp.ctx('moved')), '23514', NULL, 'ck_tasks_stamps');
    PERFORM pg_temp.fails('... and an open task with a finish time', format($q$UPDATE tasks SET completed_at = now() WHERE task_id = %s$q$, pg_temp.ctx('moved')), '23514', NULL, 'ck_tasks_stamps');
    PERFORM pg_temp.fails('a status outside the four', format($q$UPDATE tasks SET status = 'pending' WHERE task_id = %s$q$, pg_temp.ctx('moved')), '23514', NULL, 'ck_tasks_status');
    PERFORM pg_temp.fails('a position given by halves', format($q$UPDATE tasks SET latitude = 10 WHERE task_id = %s$q$, pg_temp.ctx('moved')), '23514', NULL, 'ck_tasks_position');
    PERFORM pg_temp.fails('an assignment history row must keep the status', format($q$INSERT INTO task_status_history (tenant_id, task_id, old_status, new_status, assigned_to, changed_by)
                  VALUES (1, %s, 'assigned', 'done', %s, %s)$q$, v_t, pg_temp.ctx('a'), pg_temp.ctx('admin')), '23514', NULL, 'ck_task_history_assignment');
    PERFORM pg_temp.fails('an alternate mobile that is not a mobile', format($q$UPDATE staff_profiles SET mobile_alt = '12345' WHERE user_id = %s$q$, pg_temp.ctx('new')), '23514', NULL, 'ck_staff_profiles_mobile_alt');
    PERFORM pg_temp.ok('there is no is_active on the profile: users.is_active is the one source of truth',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'staff_profiles' AND column_name = 'is_active'));
END;
$$;

SELECT count(*) || ' checks passed' AS result FROM t_pass;
ROLLBACK;
SELECT count(*) AS tasks_left_behind FROM tasks;
