-- The newest tickets a user raised, any status, newest first. is_unassigned lets the screen show "Not assigned yet".
CREATE OR REPLACE FUNCTION fn_get_my_tickets(p_tenant_id integer, p_user_id integer, p_limit integer)
RETURNS TABLE (ticket_id bigint, ticket_no varchar, issue_text varchar, customer_name varchar, status varchar, assigned_to_name varchar,
               is_unassigned boolean, created_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT v.ticket_id, v.ticket_no, v.issue_text, v.customer_name, v.status, v.assigned_to_name, v.is_unassigned, v.created_at
      FROM vw_ticket_summary v
     WHERE v.tenant_id = p_tenant_id AND v.created_by = p_user_id
     ORDER BY v.created_at DESC, v.ticket_id DESC
     LIMIT p_limit;
$$;
