-- The people a task can be given to: active staff-type users whose role can see My work, with how much open work each has (so the
-- person choosing can see who is free). For the assignee picker; it exists so someone who assigns tasks does not need the Users screen.
-- (plpgsql, not sql: it calls fn_role_can_receive_work, which is applied after it, and a SQL function is checked when created.)
CREATE OR REPLACE FUNCTION fn_get_task_assignees(p_tenant_id integer)
RETURNS TABLE (user_id integer, full_name varchar, role_name varchar, open_tasks bigint, open_tickets bigint)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT u.user_id, u.full_name, r.role_name,
           (SELECT count(*) FROM tasks t WHERE t.tenant_id = p_tenant_id AND t.assigned_to = u.user_id AND t.status IN ('assigned', 'in_progress')),
           (SELECT count(*) FROM tickets k WHERE k.tenant_id = p_tenant_id AND k.assigned_to = u.user_id AND k.status IN ('open', 'in_progress'))
      FROM users u
      JOIN roles r ON r.role_id = u.role_id
     WHERE u.tenant_id = p_tenant_id AND u.is_active AND u.user_type = 'staff'
       AND fn_role_can_receive_work(p_tenant_id, u.role_id)
     ORDER BY u.full_name, u.user_id;
END;
$$;
