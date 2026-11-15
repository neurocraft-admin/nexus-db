-- Module 7 (Tickets). Run after every release. Raises an exception naming the first thing that is missing or wrong.
DO $$
DECLARE
    v_name text;
    c_tables CONSTANT text[] := ARRAY['issue_types', 'tickets', 'ticket_status_history', 'ticket_attachments'];
    c_functions CONSTANT text[] := ARRAY[
        'fn_get_issue_types', 'fn_save_issue_type', 'sp_assert_ticket_assignee', 'sp_check_ticket_status_move',
        'sp_check_ticket_fields', 'sp_assert_ticket_customer', 'sp_assert_no_active_ticket', 'fn_add_ticket_attachment', 'fn_create_ticket',
        'sp_check_ticket_filters', 'fn_get_tickets', 'fn_get_ticket_by_id', 'fn_get_ticket_status_history',
        'fn_get_ticket_attachments', 'fn_get_ticket_attachment', 'fn_get_ticket_assignees',
        'fn_get_open_tickets_by_mobile', 'sp_change_ticket_status', 'sp_assign_ticket', 'fn_block_ticket_history_change'];
    c_fk_columns CONSTANT text[] := ARRAY[
        'tickets.customer_id', 'tickets.issue_type_id', 'tickets.assigned_to', 'tickets.created_by',
        'ticket_status_history.ticket_id', 'ticket_status_history.assigned_to', 'ticket_status_history.changed_by',
        'ticket_attachments.ticket_id'];
BEGIN
    FOREACH v_name IN ARRAY ARRAY['22_tickets_schema.sql', '23_tickets_menu.sql'] LOOP
        IF NOT EXISTS (SELECT 1 FROM deployment_log d WHERE d.script_name = v_name) THEN
            RAISE EXCEPTION 'Script not applied: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_tables LOOP
        IF to_regclass('public.' || v_name) IS NULL THEN
            RAISE EXCEPTION 'Table missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_functions LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = v_name) THEN
            RAISE EXCEPTION 'Function missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['ck_tickets_status', 'ck_tickets_source', 'ck_tickets_issue', 'ck_tickets_creator', 'ck_tickets_stamps',
                                  'uq_tickets_tenant_no', 'ck_ticket_history_assignment', 'ck_ticket_attachments_type',
                                  'ck_ticket_attachments_size', 'uq_ticket_attachments_stored_name'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = v_name) THEN
            RAISE EXCEPTION 'Constraint missing: %', v_name;
        END IF;
    END LOOP;
    -- uq_tickets_active_customer is the guarantee behind "one active ticket per customer".
    FOREACH v_name IN ARRAY ARRAY['uq_tickets_active_customer', 'uq_issue_types_tenant_name', 'ix_tickets_tenant_status'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = v_name) THEN
            RAISE EXCEPTION 'Index missing: %', v_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'uq_tickets_active_customer'
                      AND indexdef ILIKE '%open%in_progress%') THEN
        RAISE EXCEPTION 'uq_tickets_active_customer does not cover open and in_progress tickets';
    END IF;
    -- Every foreign key of the module is the leading column of some index.
    FOREACH v_name IN ARRAY c_fk_columns LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_indexes i
                        WHERE i.tablename = split_part(v_name, '.', 1)
                          AND i.indexdef ~ ('\(' || split_part(v_name, '.', 2) || '[,)]')) THEN
            RAISE EXCEPTION 'No index on the foreign key %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['trg_ticket_status_history_no_change', 'trg_ticket_status_history_no_truncate'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = v_name) THEN
            RAISE EXCEPTION 'Trigger missing: %', v_name;
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM issue_types t WHERE t.tenant_id = 1 AND t.is_active) < 1 THEN
        RAISE EXCEPTION 'No active issue types are seeded';
    END IF;
    IF EXISTS (SELECT 1 FROM issue_types t WHERE lower(t.issue_type_name) = 'other') THEN
        RAISE EXCEPTION 'There is an "Other" issue type: Other is free text, not a type (ck_tickets_issue)';
    END IF;
    FOREACH v_name IN ARRAY ARRAY['tickets', 'issue_types'] LOOP
        IF NOT EXISTS (SELECT 1 FROM resources WHERE resource_code = v_name) THEN
            RAISE EXCEPTION 'Resource missing: %', v_name;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM role_permissions rp JOIN roles r ON r.role_id = rp.role_id
                         JOIN resources x ON x.resource_id = rp.resource_id
                        WHERE r.role_name = 'Admin' AND x.resource_code = v_name AND rp.can_view AND rp.can_create AND rp.can_update) THEN
            RAISE EXCEPTION 'Admin does not have view, create and update on %', v_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM menu_items WHERE url = '/service/tickets' AND parent_id IS NOT NULL AND icon = 'ticket') THEN
        RAISE EXCEPTION 'Menu item missing: /service/tickets';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM menu_items WHERE url = '/issue-types' AND parent_id IS NOT NULL AND icon = 'tag') THEN
        RAISE EXCEPTION 'Menu item missing: /issue-types';
    END IF;
    -- Consistency of the data: every ticket has its first history row, and a ticket's status is the new status of its
    -- latest status-change row (assignment rows keep the status as it was).
    IF EXISTS (SELECT 1 FROM tickets t WHERE NOT EXISTS (
                SELECT 1 FROM ticket_status_history h WHERE h.ticket_id = t.ticket_id AND h.old_status IS NULL AND h.new_status = 'open')) THEN
        RAISE EXCEPTION 'A ticket has no first history row';
    END IF;
    IF EXISTS (SELECT 1 FROM tickets t WHERE t.status <> (
                SELECT h.new_status FROM ticket_status_history h WHERE h.ticket_id = t.ticket_id ORDER BY h.history_id DESC LIMIT 1)) THEN
        RAISE EXCEPTION 'A ticket''s status does not match its latest history row';
    END IF;

    -- The API connects as nexus_app: it must be able to use what was just created.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_app') THEN
        FOREACH v_name IN ARRAY c_tables LOOP
            IF NOT has_table_privilege('nexus_app', 'public.' || v_name, 'SELECT,INSERT') THEN
                RAISE EXCEPTION 'nexus_app cannot use table %', v_name;
            END IF;
        END LOOP;
        FOR v_name IN SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = ANY (c_functions) LOOP
            IF NOT has_function_privilege('nexus_app', v_name, 'EXECUTE') THEN
                RAISE EXCEPTION 'nexus_app cannot execute %', v_name;
            END IF;
        END LOOP;
    END IF;
END;
$$;
