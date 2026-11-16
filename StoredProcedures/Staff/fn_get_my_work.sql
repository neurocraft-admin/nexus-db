-- One person's work for the staff dashboard, from vw_staff_work, in three groups (bucket):
--   today     tasks that are open and scheduled for today (business time zone) or EARLIER (is_overdue says it is before today), and
--             EVERY open ticket (a ticket has no schedule: it is a job now)
--   upcoming  open tasks scheduled for a later day, and open tasks with no schedule
--   done      tasks that are done or cancelled and tickets that are resolved or closed, finished in the last 7 days
-- Only this user's own rows are ever returned: p_user_id comes from the signed-in user, never from the request. Within a group the
-- order is the scheduled time (unscheduled last), then the number.
CREATE OR REPLACE FUNCTION fn_get_my_work(p_tenant_id integer, p_user_id integer)
RETURNS TABLE (work_kind varchar, work_id bigint, reference_no varchar, title varchar, work_type varchar, customer_name varchar,
               customer_mobile varchar, address varchar, latitude numeric, longitude numeric, scheduled_at timestamptz,
               status varchar, bucket varchar, is_overdue boolean, finished_at timestamptz)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    c_done_days   CONSTANT integer := 7;
    v_today_start timestamptz := fn_business_day_start(p_tenant_id, fn_business_today(p_tenant_id));
    v_next_start  timestamptz := fn_business_day_start(p_tenant_id, fn_business_today(p_tenant_id) + 1);
BEGIN
    RETURN QUERY
    SELECT s.work_kind, s.work_id, s.reference_no, s.title, s.work_type, s.customer_name, s.customer_mobile, s.address, s.latitude,
           s.longitude, s.scheduled_at, s.status, s.bucket, s.is_overdue, s.finished_at
      FROM (SELECT w.work_kind, w.work_id, w.reference_no, w.title, w.work_type, w.customer_name, w.customer_mobile, w.address,
                   w.latitude::numeric, w.longitude::numeric, w.scheduled_at, w.status, w.finished_at,
                   (CASE WHEN w.status IN ('assigned', 'open', 'in_progress') THEN
                             CASE WHEN w.work_kind = 'ticket' OR (w.scheduled_at IS NOT NULL AND w.scheduled_at < v_next_start)
                                  THEN 'today' ELSE 'upcoming' END
                         WHEN w.finished_at >= now() - make_interval(days => c_done_days) THEN 'done'
                    END)::varchar AS bucket,
                   (w.work_kind = 'task' AND w.status IN ('assigned', 'in_progress') AND w.scheduled_at < v_today_start) AS is_overdue
              FROM vw_staff_work w
             WHERE w.tenant_id = p_tenant_id AND w.user_id = p_user_id) s
     WHERE s.bucket IS NOT NULL
     ORDER BY CASE s.bucket WHEN 'today' THEN 1 WHEN 'upcoming' THEN 2 ELSE 3 END, s.scheduled_at NULLS LAST, s.reference_no;
END;
$$;
