-- Edits an open task's details (not its assignee or status: those go through sp_assign_task and sp_change_task_status). The row is
-- locked first. A finished task (done or cancelled) cannot be edited.
--   P0002 not found     - unknown task
--   NX409 rule conflict - the task is done or cancelled
CREATE OR REPLACE PROCEDURE sp_update_task(
    p_tenant_id integer, p_task_id bigint, p_task_type varchar, p_title varchar, p_description varchar, p_customer_id bigint,
    p_ticket_id bigint, p_scheduled_at timestamptz, p_visit_address varchar, p_latitude numeric, p_longitude numeric)
LANGUAGE plpgsql AS $$
DECLARE
    v_status varchar;
BEGIN
    SELECT t.status INTO v_status FROM tasks t WHERE t.task_id = p_task_id AND t.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task % not found', p_task_id USING ERRCODE = 'P0002';
    END IF;
    IF v_status IN ('done', 'cancelled') THEN
        RAISE EXCEPTION 'A % task cannot be edited', v_status USING ERRCODE = 'NX409', COLUMN = 'status';
    END IF;
    UPDATE tasks
       SET task_type = p_task_type, title = btrim(p_title), description = NULLIF(btrim(p_description), ''), customer_id = p_customer_id,
           ticket_id = p_ticket_id, scheduled_at = p_scheduled_at, visit_address = NULLIF(btrim(p_visit_address), ''),
           latitude = p_latitude, longitude = p_longitude, updated_at = now()
     WHERE tasks.task_id = p_task_id AND tasks.tenant_id = p_tenant_id;
END;
$$;
