-- One file for the authenticated download: where it is stored and what to call it. No rows when the file does not belong
-- to that ticket, or the ticket is not visible to this user, so a staff user cannot fetch a file of someone else's ticket.
CREATE OR REPLACE FUNCTION fn_get_ticket_attachment(
    p_tenant_id integer, p_ticket_id bigint, p_attachment_id bigint, p_visible_to integer)
RETURNS TABLE (original_name varchar, stored_name varchar, content_type varchar, size_bytes integer)
LANGUAGE sql STABLE AS $$
    SELECT a.original_name, a.stored_name, a.content_type, a.size_bytes
      FROM ticket_attachments a
      JOIN tickets t ON t.ticket_id = a.ticket_id
     WHERE a.tenant_id = p_tenant_id AND t.tenant_id = p_tenant_id
       AND a.ticket_id = p_ticket_id AND a.attachment_id = p_attachment_id
       AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to OR t.created_by = p_visible_to);
$$;
