-- The portal's Check Status. The customer's ACTIVE tickets only (open and in progress; resolved and closed are hidden),
-- found by the registered mobile (already in the stored form; the API normalises it). Nothing else about the ticket
-- or the customer leaves the database: no ids, no internal notes, no history, and the technician is shown by FIRST NAME only.
-- A mobile that belongs to no active customer returns no rows, the same as a customer with no open ticket.
CREATE OR REPLACE FUNCTION fn_get_open_tickets_by_mobile(p_tenant_id integer, p_mobile varchar)
RETURNS TABLE (ticket_no varchar, issue_text varchar, status varchar, technician_first_name varchar, created_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT t.ticket_no, COALESCE(it.issue_type_name, t.other_issue_text), t.status,
           NULLIF(split_part(btrim(u.full_name), ' ', 1), ''), t.created_at
      FROM tickets t
      JOIN customers c ON c.customer_id = t.customer_id
      LEFT JOIN issue_types it ON it.issue_type_id = t.issue_type_id
      LEFT JOIN users u ON u.user_id = t.assigned_to
     WHERE t.tenant_id = p_tenant_id AND c.tenant_id = p_tenant_id
       AND c.mobile = p_mobile AND c.is_active
       AND t.status IN ('open', 'in_progress')
     ORDER BY t.created_at DESC, t.ticket_id DESC;
$$;
