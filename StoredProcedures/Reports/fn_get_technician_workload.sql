-- What each person who can be given work has on today: their open tasks scheduled today or EARLIER (the My work "Today" rule), how many of
-- those are overdue (before today), and their open tickets; items = tasks + tickets. Everyone is listed, including people with nothing.
-- "Can be given work" = an active staff-type user whose role has my_work view (fn_role_can_receive_work). Busiest first.
CREATE OR REPLACE FUNCTION fn_get_technician_workload(p_tenant_id integer, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (user_id integer, full_name varchar, tasks_today bigint, overdue_tasks bigint, open_tickets bigint, items bigint)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_day         date := fn_business_date_of(p_tenant_id, COALESCE(p_as_of, now()));
    v_today_start timestamptz := fn_business_day_start(p_tenant_id, v_day);
    v_next_start  timestamptz := fn_business_day_start(p_tenant_id, v_day + 1);
BEGIN
    RETURN QUERY
    SELECT w.user_id, w.full_name, w.tasks_today, w.overdue_tasks, w.open_tickets, w.tasks_today + w.open_tickets
      FROM (SELECT u.user_id, u.full_name,
                   (SELECT count(*) FROM tasks t WHERE t.tenant_id = p_tenant_id AND t.assigned_to = u.user_id
                       AND t.status IN ('assigned', 'in_progress') AND t.scheduled_at < v_next_start) AS tasks_today,
                   (SELECT count(*) FROM tasks t WHERE t.tenant_id = p_tenant_id AND t.assigned_to = u.user_id
                       AND t.status IN ('assigned', 'in_progress') AND t.scheduled_at < v_today_start) AS overdue_tasks,
                   (SELECT count(*) FROM tickets k WHERE k.tenant_id = p_tenant_id AND k.assigned_to = u.user_id
                       AND k.status IN ('open', 'in_progress')) AS open_tickets
              FROM users u
             WHERE u.tenant_id = p_tenant_id AND u.is_active AND u.user_type = 'staff' AND fn_role_can_receive_work(p_tenant_id, u.role_id)) w
     ORDER BY w.tasks_today + w.open_tickets DESC, w.full_name, w.user_id;
END;
$$;
