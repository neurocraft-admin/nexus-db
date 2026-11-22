-- Open tickets nobody has been given yet, oldest first, with the number of them in all (total_count). A task is always created with an
-- assignee, so only tickets can wait for one. age_days is whole days since it was raised.
CREATE OR REPLACE FUNCTION fn_get_needs_assignment(p_tenant_id integer, p_limit integer, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (ticket_id bigint, ticket_no varchar, issue_text varchar, customer_name varchar, created_at timestamptz, age_days integer,
               total_count bigint)
LANGUAGE sql STABLE AS $$
    SELECT v.ticket_id, v.ticket_no, v.issue_text, v.customer_name, v.created_at,
           floor(extract(epoch FROM (COALESCE(p_as_of, now()) - v.created_at)) / 86400)::integer, count(*) OVER ()
      FROM vw_ticket_summary v
     WHERE v.tenant_id = p_tenant_id AND v.is_open AND v.is_unassigned
     ORDER BY v.created_at, v.ticket_id
     LIMIT p_limit;
$$;
