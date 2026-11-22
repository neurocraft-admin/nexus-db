-- The ticket list with filters and paging. Each row carries total_count (rows matching the filter before paging).
-- Every filter is optional (NULL = no filter):
--   p_status       open, in_progress, resolved or closed; or 'active' for open and in progress together
--   p_assigned_to, p_customer_id, p_source ('portal' or 'internal')
--   p_search       the ticket number, customer name, customer mobile or issue text anywhere, ignoring case (plain text)
--   p_from, p_to   the day the ticket was raised, in the business time zone, inclusive
-- p_visible_to is the staff user's id: a staff user sees only the tickets assigned to them or raised by them, enforced here and not only
-- in the screen; NULL (an admin or manager) sees all.
--   22023 invalid parameter - an unknown status or source
CREATE OR REPLACE FUNCTION fn_get_tickets(
    p_tenant_id integer, p_status varchar, p_assigned_to integer, p_customer_id bigint, p_source varchar,
    p_search varchar, p_from date, p_to date, p_visible_to integer, p_limit integer, p_offset integer)
RETURNS TABLE (ticket_id bigint, ticket_no varchar, customer_id bigint, customer_name varchar, issue_text varchar,
               status varchar, source varchar, assigned_to integer, assigned_to_name varchar, created_at timestamptz,
               total_count bigint)
LANGUAGE plpgsql AS $$
BEGIN
    CALL sp_check_ticket_filters(p_status, p_source);
    RETURN QUERY
    SELECT t.ticket_id, t.ticket_no, t.customer_id, c.customer_name, COALESCE(it.issue_type_name, t.other_issue_text),
           t.status, t.source, t.assigned_to, u.full_name, t.created_at, count(*) OVER ()
      FROM tickets t
      JOIN customers c ON c.customer_id = t.customer_id
      LEFT JOIN issue_types it ON it.issue_type_id = t.issue_type_id
      LEFT JOIN users u ON u.user_id = t.assigned_to
     WHERE t.tenant_id = p_tenant_id
       AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to OR t.created_by = p_visible_to)
       AND (p_status IS NULL OR t.status = p_status OR (p_status = 'active' AND t.status IN ('open', 'in_progress')))
       AND (p_assigned_to IS NULL OR t.assigned_to = p_assigned_to)
       AND (p_customer_id IS NULL OR t.customer_id = p_customer_id)
       AND (p_source IS NULL OR t.source = p_source)
       AND (p_search IS NULL OR btrim(p_search) = ''
            OR position(lower(btrim(p_search)) IN lower(t.ticket_no || ' ' || c.customer_name || ' ' || c.mobile || ' '
                                                        || COALESCE(it.issue_type_name, t.other_issue_text))) > 0)
       AND (p_from IS NULL OR t.created_at >= fn_business_day_start(p_tenant_id, p_from))
       AND (p_to IS NULL OR t.created_at < fn_business_day_start(p_tenant_id, p_to + 1))
     ORDER BY t.created_at DESC, t.ticket_id DESC
     LIMIT p_limit OFFSET COALESCE(p_offset, 0);
END;
$$;
