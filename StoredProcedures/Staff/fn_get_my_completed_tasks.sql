-- Report: the tasks this person finished (status done) with the completion in the given days (business time zone, inclusive), newest
-- first, with a total. p_user_id comes from the signed-in user, never from the request.
--   22023 invalid parameter - an end date before the start date (COLUMN to)
CREATE OR REPLACE FUNCTION fn_get_my_completed_tasks(p_tenant_id integer, p_user_id integer, p_from date, p_to date)
RETURNS TABLE (task_id bigint, task_no varchar, title varchar, customer_name varchar, completed_at timestamptz,
               completion_note varchar, total_count bigint)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_to < p_from THEN
        RAISE EXCEPTION 'The end date cannot be before the start date' USING ERRCODE = '22023', COLUMN = 'to';
    END IF;
    RETURN QUERY
    SELECT t.task_id, t.task_no, t.title, c.customer_name, t.completed_at, t.completion_note, count(*) OVER ()
      FROM tasks t
      LEFT JOIN customers c ON c.customer_id = t.customer_id
     WHERE t.tenant_id = p_tenant_id AND t.assigned_to = p_user_id AND t.status = 'done'
       AND (p_from IS NULL OR t.completed_at >= fn_business_day_start(p_tenant_id, p_from))
       AND (p_to IS NULL OR t.completed_at < fn_business_day_start(p_tenant_id, p_to + 1))
     ORDER BY t.completed_at DESC, t.task_id DESC;
END;
$$;
