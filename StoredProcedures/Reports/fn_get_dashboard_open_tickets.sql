-- The oldest open (open or in progress) tickets, oldest first: what is waiting longest. age_days is whole days since it was raised; is_overdue
-- when it is older than ticket_overdue_days. total_count is how many open tickets there are in all.
CREATE OR REPLACE FUNCTION fn_get_dashboard_open_tickets(p_tenant_id integer, p_limit integer, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (ticket_id bigint, ticket_no varchar, issue_text varchar, customer_name varchar, status varchar, assigned_to_name varchar,
               created_at timestamptz, age_days integer, is_overdue boolean, total_count bigint)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_now     timestamptz := COALESCE(p_as_of, now());
    v_overdue interval := make_interval(days => fn_ticket_overdue_days(p_tenant_id));
BEGIN
    RETURN QUERY
    SELECT v.ticket_id, v.ticket_no, v.issue_text, v.customer_name, v.status, v.assigned_to_name, v.created_at,
           floor(extract(epoch FROM (v_now - v.created_at)) / 86400)::integer, v.created_at < v_now - v_overdue, count(*) OVER ()
      FROM vw_ticket_summary v
     WHERE v.tenant_id = p_tenant_id AND v.is_open
     ORDER BY v.created_at, v.ticket_id
     LIMIT p_limit;
END;
$$;
