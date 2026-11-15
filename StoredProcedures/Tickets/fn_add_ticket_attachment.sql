-- Saves the row for a file that is already stored (under its random name) and returns the attachment id. fn_create_ticket
-- calls it inside its own transaction, so a ticket and its file row are saved together or not at all. The size and type
-- limits are table CHECKs; the API checks them first, from the file's own bytes.
--   P0002 not found - unknown ticket
CREATE OR REPLACE FUNCTION fn_add_ticket_attachment(
    p_tenant_id integer, p_ticket_id bigint, p_original_name varchar, p_stored_name varchar,
    p_content_type varchar, p_size_bytes integer)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_attachment_id bigint;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tickets t WHERE t.ticket_id = p_ticket_id AND t.tenant_id = p_tenant_id) THEN
        RAISE EXCEPTION 'Ticket % not found', p_ticket_id USING ERRCODE = 'P0002';
    END IF;
    INSERT INTO ticket_attachments (tenant_id, ticket_id, original_name, stored_name, content_type, size_bytes)
    VALUES (p_tenant_id, p_ticket_id, btrim(p_original_name), p_stored_name, p_content_type, p_size_bytes)
    RETURNING ticket_attachments.attachment_id INTO v_attachment_id;
    RETURN v_attachment_id;
END;
$$;
