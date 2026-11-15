-- The files of one ticket, for the detail screen: names and sizes only, never the stored name (that is only for the
-- download, fn_get_ticket_attachment). Empty when the ticket is not visible to this user.
CREATE OR REPLACE FUNCTION fn_get_ticket_attachments(p_tenant_id integer, p_ticket_id bigint, p_visible_to integer)
RETURNS TABLE (attachment_id bigint, original_name varchar, content_type varchar, size_bytes integer, uploaded_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT a.attachment_id, a.original_name, a.content_type, a.size_bytes, a.uploaded_at
      FROM ticket_attachments a
      JOIN tickets t ON t.ticket_id = a.ticket_id
     WHERE a.tenant_id = p_tenant_id AND t.tenant_id = p_tenant_id AND a.ticket_id = p_ticket_id
       AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to)
     ORDER BY a.attachment_id;
$$;
