-- The timeline of one task, oldest first. Empty when the task is not visible to this user (see fn_get_task_by_id). A row is a status
-- change (old status differs from new), the first row (no old status, the first assignee), or a reassignment (assigned_to set and
-- the two statuses the same).
CREATE OR REPLACE FUNCTION fn_get_task_history(p_tenant_id integer, p_task_id bigint, p_visible_to integer)
RETURNS TABLE (history_id bigint, old_status varchar, new_status varchar, assigned_to integer, assigned_to_name varchar,
               changed_by integer, changed_by_name varchar, note varchar, changed_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT h.history_id, h.old_status, h.new_status, h.assigned_to, a.full_name, h.changed_by, cb.full_name, h.note, h.changed_at
      FROM task_status_history h
      JOIN tasks t ON t.task_id = h.task_id
      LEFT JOIN users a ON a.user_id = h.assigned_to
      LEFT JOIN users cb ON cb.user_id = h.changed_by
     WHERE h.tenant_id = p_tenant_id AND t.tenant_id = p_tenant_id AND h.task_id = p_task_id
       AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to)
     ORDER BY h.history_id;
$$;
