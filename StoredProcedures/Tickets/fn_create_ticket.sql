-- Raises a ticket and returns its id and number. Everything happens in this one transaction: the number (from the
-- counter, so a refused ticket does not use one up and there are no gaps), the ticket, its first history row ('open',
-- no old status) and, when a file was stored, its attachment row. The customer must be active.
-- p_source is 'portal' (p_created_by NULL: the customer has no login) or 'internal' (p_created_by is the staff user).
-- One of p_issue_type_id or p_other_issue_text. The attachment arguments are all given or all NULL.
--   22023 / P0002 / NX409   - the field errors of sp_check_ticket_fields; an unknown customer is P0002 (COLUMN customerId)
--   NX409 rule conflict     - a deactivated customer (COLUMN customerId); the customer already has an active ticket:
--                             the message and DETAIL give its number, also when two submissions arrive at the same
--                             moment (the unique index decides and the loser gets this same answer)
CREATE OR REPLACE FUNCTION fn_create_ticket(
    p_tenant_id integer, p_customer_id bigint, p_issue_type_id integer, p_other_issue_text varchar,
    p_description varchar, p_source varchar, p_created_by integer, p_attachment_name varchar,
    p_attachment_stored varchar, p_attachment_type varchar, p_attachment_size integer)
RETURNS TABLE (ticket_id bigint, ticket_no varchar)
LANGUAGE plpgsql AS $$
DECLARE
    v_ticket_id  bigint;
    v_ticket_no  varchar;
    v_constraint text;
BEGIN
    CALL sp_assert_ticket_customer(p_tenant_id, p_customer_id);
    CALL sp_check_ticket_fields(p_tenant_id, p_issue_type_id, p_other_issue_text, p_description, p_source, p_created_by,
                                p_attachment_name, p_attachment_stored, p_attachment_type, p_attachment_size);
    CALL sp_assert_no_active_ticket(p_tenant_id, p_customer_id);
    INSERT INTO tickets (tenant_id, ticket_no, customer_id, issue_type_id, other_issue_text, description, source, created_by)
    VALUES (p_tenant_id, fn_next_document_no(p_tenant_id, 'TKT'), p_customer_id, p_issue_type_id,
            NULLIF(btrim(p_other_issue_text), ''), btrim(p_description), p_source, p_created_by)
    RETURNING tickets.ticket_id, tickets.ticket_no INTO v_ticket_id, v_ticket_no;
    INSERT INTO ticket_status_history (tenant_id, ticket_id, old_status, new_status, changed_by)
    VALUES (p_tenant_id, v_ticket_id, NULL, 'open', p_created_by);
    IF p_attachment_stored IS NOT NULL THEN
        PERFORM fn_add_ticket_attachment(p_tenant_id, v_ticket_id, p_attachment_name, p_attachment_stored,
                                         p_attachment_type, p_attachment_size);
    END IF;
    RETURN QUERY SELECT v_ticket_id, v_ticket_no;
EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint = 'uq_tickets_active_customer' THEN
        CALL sp_assert_no_active_ticket(p_tenant_id, p_customer_id);
    END IF;
    RAISE;
END;
$$;
