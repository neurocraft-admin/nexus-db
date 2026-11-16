-- One task's detail (its history is fn_get_task_history). No rows when the task does not exist, belongs to another tenant, or is not
-- visible to this user: a staff user (p_visible_to is their id) gets nothing for a task assigned to someone else, the same as for one
-- that does not exist, so the API answers 404 for both. visit_address is what was typed; address is what to show (the typed one,
-- else the customer's).
CREATE OR REPLACE FUNCTION fn_get_task_by_id(p_tenant_id integer, p_task_id bigint, p_visible_to integer)
RETURNS TABLE (task_id bigint, task_no varchar, task_type varchar, title varchar, description varchar, customer_id bigint,
               customer_name varchar, customer_mobile varchar, ticket_id bigint, ticket_no varchar, assigned_to integer,
               assigned_to_name varchar, scheduled_at timestamptz, visit_address varchar, address varchar, latitude numeric,
               longitude numeric, status varchar, completion_note varchar, completed_at timestamptz, created_by integer,
               created_by_name varchar, created_at timestamptz, updated_at timestamptz, is_overdue boolean)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_today_start timestamptz := fn_business_day_start(p_tenant_id, fn_business_today(p_tenant_id));
BEGIN
    RETURN QUERY
    SELECT t.task_id, t.task_no, t.task_type, t.title, t.description, t.customer_id, c.customer_name, c.mobile, t.ticket_id, k.ticket_no,
           t.assigned_to, a.full_name, t.scheduled_at, t.visit_address, COALESCE(t.visit_address, c.address), t.latitude, t.longitude,
           t.status, t.completion_note, t.completed_at, t.created_by, cb.full_name, t.created_at, t.updated_at,
           (t.status IN ('assigned', 'in_progress') AND t.scheduled_at < v_today_start)
      FROM tasks t
      LEFT JOIN customers c ON c.customer_id = t.customer_id
      LEFT JOIN tickets k ON k.ticket_id = t.ticket_id
      JOIN users a ON a.user_id = t.assigned_to
      JOIN users cb ON cb.user_id = t.created_by
     WHERE t.tenant_id = p_tenant_id AND t.task_id = p_task_id
       AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to);
END;
$$;
