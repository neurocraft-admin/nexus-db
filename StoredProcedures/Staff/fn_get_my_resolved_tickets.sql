-- Report: the tickets this person MOVED TO RESOLVED (taken from the ticket's history: who changed it, not who it is assigned to now)
-- in the given days (business time zone, inclusive). A ticket resolved by this person more than once (it was reopened) appears once,
-- with the latest time. Newest first, with a total. p_user_id comes from the signed-in user, never from the request.
--   22023 invalid parameter - an end date before the start date (COLUMN to)
CREATE OR REPLACE FUNCTION fn_get_my_resolved_tickets(p_tenant_id integer, p_user_id integer, p_from date, p_to date)
RETURNS TABLE (ticket_id bigint, ticket_no varchar, customer_name varchar, issue_text varchar, resolved_at timestamptz,
               status varchar, total_count bigint)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_to < p_from THEN
        RAISE EXCEPTION 'The end date cannot be before the start date' USING ERRCODE = '22023', COLUMN = 'to';
    END IF;
    RETURN QUERY
    SELECT r.ticket_id, k.ticket_no, c.customer_name, COALESCE(it.issue_type_name, k.other_issue_text)::varchar, r.resolved_at, k.status,
           count(*) OVER ()
      FROM (SELECT h.ticket_id, max(h.changed_at) AS resolved_at
              FROM ticket_status_history h
             WHERE h.tenant_id = p_tenant_id AND h.changed_by = p_user_id AND h.new_status = 'resolved' AND h.old_status IS DISTINCT FROM h.new_status
               AND (p_from IS NULL OR h.changed_at >= fn_business_day_start(p_tenant_id, p_from))
               AND (p_to IS NULL OR h.changed_at < fn_business_day_start(p_tenant_id, p_to + 1))
             GROUP BY h.ticket_id) r
      JOIN tickets k ON k.ticket_id = r.ticket_id
      JOIN customers c ON c.customer_id = k.customer_id
      LEFT JOIN issue_types it ON it.issue_type_id = k.issue_type_id
     WHERE k.tenant_id = p_tenant_id
     ORDER BY r.resolved_at DESC, r.ticket_id DESC;
END;
$$;
