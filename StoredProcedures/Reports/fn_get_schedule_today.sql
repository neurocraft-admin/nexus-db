-- Today's jobs in time order: the open tasks scheduled today, the OVERDUE open tasks from earlier days (marked), and today's tasks already done.
-- No notes, descriptions or completion notes: this is also what a front-desk user may see, read only. The address is the task's own, else
-- the customer's.
CREATE OR REPLACE FUNCTION fn_get_schedule_today(p_tenant_id integer, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (task_id bigint, task_no varchar, title varchar, scheduled_at timestamptz, customer_name varchar, address varchar,
               technician_name varchar, status varchar, is_overdue boolean)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_day         date := fn_business_date_of(p_tenant_id, COALESCE(p_as_of, now()));
    v_today_start timestamptz := fn_business_day_start(p_tenant_id, v_day);
    v_next_start  timestamptz := fn_business_day_start(p_tenant_id, v_day + 1);
BEGIN
    RETURN QUERY
    SELECT t.task_id, t.task_no, t.title, t.scheduled_at, c.customer_name, COALESCE(t.visit_address, c.address), u.full_name, t.status,
           (t.status IN ('assigned', 'in_progress') AND t.scheduled_at < v_today_start)
      FROM tasks t
      JOIN users u ON u.user_id = t.assigned_to
      LEFT JOIN customers c ON c.customer_id = t.customer_id
     WHERE t.tenant_id = p_tenant_id AND t.scheduled_at < v_next_start
       AND (t.status IN ('assigned', 'in_progress') OR (t.status = 'done' AND t.scheduled_at >= v_today_start))
     ORDER BY t.scheduled_at, t.task_id;
END;
$$;
