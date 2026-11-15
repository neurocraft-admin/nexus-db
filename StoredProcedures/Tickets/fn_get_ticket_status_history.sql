-- The timeline of one ticket, oldest first. Empty when the ticket is not visible to this user (see fn_get_ticket_by_id).
-- A row is either a status change (old_status differs from new_status; the first row has no old_status) or an
-- assignment (assigned_to is set and the two statuses are the same). changed_by is NULL for a ticket raised on the portal.
CREATE OR REPLACE FUNCTION fn_get_ticket_status_history(p_tenant_id integer, p_ticket_id bigint, p_visible_to integer)
RETURNS TABLE (history_id bigint, old_status varchar, new_status varchar, assigned_to integer, assigned_to_name varchar,
               changed_by integer, changed_by_name varchar, note varchar, changed_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT h.history_id, h.old_status, h.new_status, h.assigned_to, a.full_name, h.changed_by, cb.full_name, h.note, h.changed_at
      FROM ticket_status_history h
      JOIN tickets t ON t.ticket_id = h.ticket_id
      LEFT JOIN users a ON a.user_id = h.assigned_to
      LEFT JOIN users cb ON cb.user_id = h.changed_by
     WHERE h.tenant_id = p_tenant_id AND t.tenant_id = p_tenant_id AND h.ticket_id = p_ticket_id
       AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to)
     ORDER BY h.history_id;
$$;
