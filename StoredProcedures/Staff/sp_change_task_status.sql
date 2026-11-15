-- Moves a task to another status (rules: sp_check_task_status_move) and writes exactly ONE history row (old status, new status, who,
-- the note). The row is locked first, so two people acting at the same moment are decided one after the other: the second sees the
-- new status and is refused if its move no longer fits (two people completing the same task). done stamps completed_at and keeps the
-- trimmed note as the completion note; cancelled stamps completed_at. A staff user (p_visible_to is their id) can only change a task
-- assigned to them, and can start and complete it but NOT cancel it (only an administrator cancels).
--   42501 insufficient privilege - a staff user asking for cancelled
--   22023 invalid parameter - an unknown status, a note over 500 characters, or no note on done
--   P0002 not found         - unknown task or one outside p_visible_to
--   NX409 rule conflict     - a move that is not allowed (done and cancelled are final)
CREATE OR REPLACE PROCEDURE sp_change_task_status(
    p_tenant_id integer, p_task_id bigint, p_new_status varchar, p_note varchar, p_user_id integer, p_visible_to integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_old_status varchar;
    v_note       varchar := NULLIF(btrim(p_note), '');
BEGIN
    SELECT t.status INTO v_old_status
      FROM tasks t
     WHERE t.task_id = p_task_id AND t.tenant_id = p_tenant_id AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to)
       FOR UPDATE OF t;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task % not found', p_task_id USING ERRCODE = 'P0002';
    END IF;
    IF p_visible_to IS NOT NULL AND p_new_status = 'cancelled' THEN
        RAISE EXCEPTION 'Only an administrator can cancel a task' USING ERRCODE = '42501';
    END IF;
    CALL sp_check_task_status_move(v_old_status, p_new_status, v_note);
    UPDATE tasks
       SET status = p_new_status,
           completed_at = CASE WHEN p_new_status IN ('done', 'cancelled') THEN now() END,
           completion_note = CASE WHEN p_new_status = 'done' THEN v_note END,
           updated_at = now()
     WHERE tasks.task_id = p_task_id AND tasks.tenant_id = p_tenant_id;
    INSERT INTO task_status_history (tenant_id, task_id, old_status, new_status, changed_by, note)
    VALUES (p_tenant_id, p_task_id, v_old_status, p_new_status, p_user_id, v_note);
END;
$$;
