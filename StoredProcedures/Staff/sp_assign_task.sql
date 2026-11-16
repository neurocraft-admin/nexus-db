-- Gives an open task (assigned or in progress) to another staff user and writes exactly ONE history row: the status stays as it is
-- (old and new status are the same) and assigned_to says who it went to. Assigning to the person who already has it changes
-- nothing and writes nothing. ONLY NON-STAFF USERS may assign or reassign: a staff caller (p_visible_to is their id) is refused.
-- A finished task cannot be reassigned. The assignee must be an active staff user whose role can see My work.
--   42501 insufficient privilege - the caller is a staff user
--   P0002 not found     - unknown task; unknown assignee (COLUMN assignedTo)
--   NX409 rule conflict - a done or cancelled task; an assignee who is deactivated, not a staff user, or cannot see My work
CREATE OR REPLACE PROCEDURE sp_assign_task(
    p_tenant_id integer, p_task_id bigint, p_assigned_to integer, p_user_id integer, p_visible_to integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_task record;
BEGIN
    IF p_visible_to IS NOT NULL THEN
        RAISE EXCEPTION 'Only an administrator can assign or reassign a task' USING ERRCODE = '42501';
    END IF;
    SELECT t.status, t.assigned_to INTO v_task FROM tasks t WHERE t.task_id = p_task_id AND t.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task % not found', p_task_id USING ERRCODE = 'P0002';
    END IF;
    IF v_task.status IN ('done', 'cancelled') THEN
        RAISE EXCEPTION 'A % task cannot be reassigned', v_task.status USING ERRCODE = 'NX409', COLUMN = 'status';
    END IF;
    CALL sp_assert_task_assignee(p_tenant_id, p_assigned_to);
    IF v_task.assigned_to = p_assigned_to THEN
        RETURN;
    END IF;
    UPDATE tasks SET assigned_to = p_assigned_to, updated_at = now() WHERE tasks.task_id = p_task_id AND tasks.tenant_id = p_tenant_id;
    INSERT INTO task_status_history (tenant_id, task_id, old_status, new_status, assigned_to, changed_by)
    VALUES (p_tenant_id, p_task_id, v_task.status, v_task.status, p_assigned_to, p_user_id);
END;
$$;
