-- Inserts one new task and its first history row (no old status, the first assignee) and returns the id in p_task_id. The number
-- comes from the counter inside this transaction, so a refused task uses none up. Everything has already been checked by
-- sp_check_task_fields; the assignee is checked here.
--   P0002 / NX409 - from sp_assert_task_assignee (COLUMN assignedTo)
CREATE OR REPLACE PROCEDURE sp_insert_task(
    p_tenant_id integer, p_task_type varchar, p_title varchar, p_description varchar, p_customer_id bigint, p_ticket_id bigint,
    p_assigned_to integer, p_scheduled_at timestamptz, p_visit_address varchar, p_latitude numeric, p_longitude numeric,
    p_user_id integer, OUT p_task_id bigint)
LANGUAGE plpgsql AS $$
BEGIN
    CALL sp_assert_task_assignee(p_tenant_id, p_assigned_to);
    INSERT INTO tasks (tenant_id, task_no, task_type, title, description, customer_id, ticket_id, assigned_to, scheduled_at,
                       visit_address, latitude, longitude, created_by)
    VALUES (p_tenant_id, fn_next_document_no(p_tenant_id, 'TSK'), p_task_type, btrim(p_title), NULLIF(btrim(p_description), ''),
            p_customer_id, p_ticket_id, p_assigned_to, p_scheduled_at, NULLIF(btrim(p_visit_address), ''), p_latitude, p_longitude, p_user_id)
    RETURNING tasks.task_id INTO p_task_id;
    INSERT INTO task_status_history (tenant_id, task_id, old_status, new_status, assigned_to, changed_by)
    VALUES (p_tenant_id, p_task_id, NULL, 'assigned', p_assigned_to, p_user_id);
END;
$$;
