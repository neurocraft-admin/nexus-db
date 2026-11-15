-- One ticket's detail (its history is fn_get_ticket_status_history, its files fn_get_ticket_attachments). No rows when
-- the ticket does not exist, belongs to another tenant, or is not visible to this user: a staff user (p_visible_to is
-- their id) gets nothing for a ticket assigned to someone else, the same as for one that does not exist, so the API
-- answers 404 for both. created_by is NULL for a ticket raised on the portal.
CREATE OR REPLACE FUNCTION fn_get_ticket_by_id(p_tenant_id integer, p_ticket_id bigint, p_visible_to integer)
RETURNS TABLE (ticket_id bigint, ticket_no varchar, customer_id bigint, customer_name varchar, customer_mobile varchar,
               customer_address varchar, issue_type_id integer, issue_type_name varchar, other_issue_text varchar,
               issue_text varchar, description varchar, status varchar, source varchar, assigned_to integer,
               assigned_to_name varchar, resolved_at timestamptz, closed_at timestamptz, created_by integer,
               created_by_name varchar, created_at timestamptz, updated_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT t.ticket_id, t.ticket_no, t.customer_id, c.customer_name, c.mobile, c.address, t.issue_type_id,
           it.issue_type_name, t.other_issue_text, COALESCE(it.issue_type_name, t.other_issue_text), t.description,
           t.status, t.source, t.assigned_to, a.full_name, t.resolved_at, t.closed_at, t.created_by, cb.full_name,
           t.created_at, t.updated_at
      FROM tickets t
      JOIN customers c ON c.customer_id = t.customer_id
      LEFT JOIN issue_types it ON it.issue_type_id = t.issue_type_id
      LEFT JOIN users a ON a.user_id = t.assigned_to
      LEFT JOIN users cb ON cb.user_id = t.created_by
     WHERE t.tenant_id = p_tenant_id AND t.ticket_id = p_ticket_id
       AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to);
$$;
