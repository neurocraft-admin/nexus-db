-- Module 8 (Staff and tasks). Run after every release. Raises an exception naming the first thing that is missing or wrong.
DO $$
DECLARE
    v_name text;
    c_tables CONSTANT text[] := ARRAY['staff_profiles', 'tasks', 'task_status_history'];
    c_functions CONSTANT text[] := ARRAY[
        'fn_role_can_receive_work', 'sp_assert_no_open_work', 'sp_assert_task_assignee', 'fn_get_task_assignees', 'fn_get_staff',
        'fn_get_staff_by_id', 'sp_check_staff_profile', 'sp_check_staff_role_change', 'fn_save_staff', 'fn_set_staff_active',
        'fn_get_staff_task_load', 'sp_check_task_status_move', 'sp_check_task_fields', 'sp_check_task_filters', 'sp_insert_task',
        'sp_update_task', 'fn_save_task', 'sp_assign_task', 'sp_change_task_status', 'fn_get_tasks', 'fn_get_task_by_id',
        'fn_get_task_history', 'fn_get_my_work', 'fn_get_my_completed_tasks', 'fn_get_my_resolved_tickets', 'fn_block_task_history_change'];
    c_fk_columns CONSTANT text[] := ARRAY[
        'tasks.customer_id', 'tasks.ticket_id', 'tasks.assigned_to', 'tasks.created_by', 'task_status_history.task_id',
        'task_status_history.assigned_to', 'task_status_history.changed_by'];
BEGIN
    FOREACH v_name IN ARRAY ARRAY['25_staff_schema.sql', '26_staff_menu.sql'] LOOP
        IF NOT EXISTS (SELECT 1 FROM deployment_log d WHERE d.script_name = v_name) THEN
            RAISE EXCEPTION 'Script not applied: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_tables LOOP
        IF to_regclass('public.' || v_name) IS NULL THEN
            RAISE EXCEPTION 'Table missing: %', v_name;
        END IF;
    END LOOP;
    IF to_regclass('public.vw_staff_work') IS NULL THEN
        RAISE EXCEPTION 'View missing: vw_staff_work';
    END IF;
    FOREACH v_name IN ARRAY c_functions LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = v_name) THEN
            RAISE EXCEPTION 'Function missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['ck_tasks_type', 'ck_tasks_status', 'ck_tasks_stamps', 'ck_tasks_position', 'uq_tasks_tenant_no',
                                  'ck_task_history_assignment', 'ck_staff_profiles_mobile_alt'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = v_name) THEN
            RAISE EXCEPTION 'Constraint missing: %', v_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'uq_staff_profiles_tenant_code') THEN
        RAISE EXCEPTION 'Index missing: uq_staff_profiles_tenant_code';
    END IF;
    -- Every foreign key of the module is the leading column of some index.
    FOREACH v_name IN ARRAY c_fk_columns LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_indexes i
                        WHERE i.tablename = split_part(v_name, '.', 1)
                          AND i.indexdef ~ ('\(' || split_part(v_name, '.', 2) || '[,)]')) THEN
            RAISE EXCEPTION 'No index on the foreign key %', v_name;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'staff_profiles' AND column_name = 'is_active') THEN
        RAISE EXCEPTION 'staff_profiles has its own is_active: users.is_active is the one source of truth';
    END IF;
    FOREACH v_name IN ARRAY ARRAY['trg_task_status_history_no_change', 'trg_task_status_history_no_truncate'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = v_name) THEN
            RAISE EXCEPTION 'Trigger missing: %', v_name;
        END IF;
    END LOOP;
    -- Resources, Admin and Staff-role permissions, and the menu.
    FOREACH v_name IN ARRAY ARRAY['staff', 'tasks', 'my_work'] LOOP
        IF NOT EXISTS (SELECT 1 FROM resources WHERE resource_code = v_name) THEN
            RAISE EXCEPTION 'Resource missing: %', v_name;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM role_permissions rp JOIN roles r ON r.role_id = rp.role_id
                         JOIN resources x ON x.resource_id = rp.resource_id
                        WHERE r.role_name = 'Admin' AND x.resource_code = v_name AND rp.can_view AND rp.can_update) THEN
            RAISE EXCEPTION 'Admin does not have view and update on %', v_name;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM roles r WHERE r.role_name = 'Staff') AND NOT EXISTS (
        SELECT 1 FROM role_permissions rp JOIN roles r ON r.role_id = rp.role_id JOIN resources x ON x.resource_id = rp.resource_id
         WHERE r.role_name = 'Staff' AND x.resource_code = 'my_work' AND rp.can_view AND rp.can_update AND NOT rp.can_create AND NOT rp.can_delete) THEN
        RAISE EXCEPTION 'The Staff role does not have my_work view and update';
    END IF;
    FOREACH v_name IN ARRAY ARRAY['/staff|briefcase', '/service/tasks|calendar', '/staff-members|id-card'] LOOP
        IF NOT EXISTS (SELECT 1 FROM menu_items WHERE url = split_part(v_name, '|', 1) AND icon = split_part(v_name, '|', 2) AND parent_id IS NOT NULL) THEN
            RAISE EXCEPTION 'Menu item missing: %', v_name;
        END IF;
    END LOOP;
    -- Consistency of the data: every task has its first history row, and a task's status is the new status of its latest row.
    IF EXISTS (SELECT 1 FROM tasks t WHERE NOT EXISTS (
                SELECT 1 FROM task_status_history h WHERE h.task_id = t.task_id AND h.old_status IS NULL AND h.new_status = 'assigned')) THEN
        RAISE EXCEPTION 'A task has no first history row';
    END IF;
    IF EXISTS (SELECT 1 FROM tasks t WHERE t.status <> (
                SELECT h.new_status FROM task_status_history h WHERE h.task_id = t.task_id ORDER BY h.history_id DESC LIMIT 1)) THEN
        RAISE EXCEPTION 'A task''s status does not match its latest history row';
    END IF;
    IF EXISTS (SELECT 1 FROM tasks t JOIN users u ON u.user_id = t.assigned_to WHERE u.user_type <> 'staff') THEN
        RAISE EXCEPTION 'A task is assigned to someone who is not a staff user';
    END IF;

    -- The API connects as nexus_app: it must be able to use what was just created.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_app') THEN
        FOREACH v_name IN ARRAY c_tables || ARRAY['vw_staff_work'] LOOP
            IF NOT has_table_privilege('nexus_app', 'public.' || v_name, 'SELECT') THEN
                RAISE EXCEPTION 'nexus_app cannot read %', v_name;
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
