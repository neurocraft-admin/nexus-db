-- The task list with filters and paging. Each row carries total_count (rows matching the filter before paging). Every filter is
-- optional (NULL = no filter):
--   p_assigned_to, p_customer_id, p_task_type
--   p_status       assigned, in_progress, done, cancelled; or 'open' for assigned and in progress together
--   p_from, p_to   the day the task is SCHEDULED, in the business time zone, inclusive (unscheduled tasks are left out when either is given)
--   p_search       the task number, title, customer name or ticket number anywhere, ignoring case (plain text)
-- p_visible_to is the staff user's id: a staff user sees only the tasks assigned to them, enforced here and not only in the screen;
-- NULL (an administrator) sees all. is_overdue says an open task's scheduled time is before today (business time zone).
--   22023 invalid parameter - an unknown status or type, or an end date before the start date
CREATE OR REPLACE FUNCTION fn_get_tasks(
    p_tenant_id integer, p_assigned_to integer, p_status varchar, p_task_type varchar, p_from date, p_to date, p_customer_id bigint,
    p_search varchar, p_visible_to integer, p_limit integer, p_offset integer)
RETURNS TABLE (task_id bigint, task_no varchar, task_type varchar, title varchar, customer_id bigint, customer_name varchar,
               ticket_id bigint, ticket_no varchar, assigned_to integer, assigned_to_name varchar, scheduled_at timestamptz,
               status varchar, is_overdue boolean, created_at timestamptz, total_count bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_today_start timestamptz := fn_business_day_start(p_tenant_id, fn_business_today(p_tenant_id));
BEGIN
    CALL sp_check_task_filters(p_status, p_task_type, p_from, p_to);
    RETURN QUERY
    SELECT t.task_id, t.task_no, t.task_type, t.title, t.customer_id, c.customer_name, t.ticket_id, k.ticket_no, t.assigned_to, u.full_name,
           t.scheduled_at, t.status, (t.status IN ('assigned', 'in_progress') AND t.scheduled_at < v_today_start), t.created_at, count(*) OVER ()
      FROM tasks t
      LEFT JOIN customers c ON c.customer_id = t.customer_id
      LEFT JOIN tickets k ON k.ticket_id = t.ticket_id
      JOIN users u ON u.user_id = t.assigned_to
     WHERE t.tenant_id = p_tenant_id
       AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to)
       AND (p_assigned_to IS NULL OR t.assigned_to = p_assigned_to)
       AND (p_customer_id IS NULL OR t.customer_id = p_customer_id)
       AND (p_task_type IS NULL OR t.task_type = p_task_type)
       AND (p_status IS NULL OR t.status = p_status OR (p_status = 'open' AND t.status IN ('assigned', 'in_progress')))
       AND (p_from IS NULL OR t.scheduled_at >= fn_business_day_start(p_tenant_id, p_from))
       AND (p_to IS NULL OR t.scheduled_at < fn_business_day_start(p_tenant_id, p_to + 1))
       AND (p_search IS NULL OR btrim(p_search) = ''
            OR position(lower(btrim(p_search)) IN lower(t.task_no || ' ' || t.title || ' ' || COALESCE(c.customer_name, '') || ' ' || COALESCE(k.ticket_no, ''))) > 0)
     ORDER BY t.scheduled_at NULLS LAST, t.created_at DESC, t.task_id DESC
     LIMIT p_limit OFFSET COALESCE(p_offset, 0);
END;
$$;
