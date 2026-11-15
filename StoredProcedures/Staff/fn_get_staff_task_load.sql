-- Open work per active staff-type user, for the dashboard: open tasks, how many of them are overdue (scheduled before today in the
-- business time zone) and open tickets. Everyone is listed, including people with nothing open.
CREATE OR REPLACE FUNCTION fn_get_staff_task_load(p_tenant_id integer)
RETURNS TABLE (user_id integer, full_name varchar, role_name varchar, open_tasks bigint, overdue_tasks bigint, open_tickets bigint)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_today_start timestamptz := fn_business_day_start(p_tenant_id, fn_business_today(p_tenant_id));
BEGIN
    RETURN QUERY
    SELECT u.user_id, u.full_name, r.role_name,
           (SELECT count(*) FROM tasks t WHERE t.tenant_id = p_tenant_id AND t.assigned_to = u.user_id AND t.status IN ('assigned', 'in_progress')),
           (SELECT count(*) FROM tasks t WHERE t.tenant_id = p_tenant_id AND t.assigned_to = u.user_id AND t.status IN ('assigned', 'in_progress')
               AND t.scheduled_at < v_today_start),
           (SELECT count(*) FROM tickets k WHERE k.tenant_id = p_tenant_id AND k.assigned_to = u.user_id AND k.status IN ('open', 'in_progress'))
      FROM users u
      JOIN roles r ON r.role_id = u.role_id
     WHERE u.tenant_id = p_tenant_id AND u.is_active AND u.user_type = 'staff'
     ORDER BY u.full_name, u.user_id;
END;
$$;
