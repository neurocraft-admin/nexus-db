-- Moves a ticket to another status (rules: sp_check_ticket_status_move) and writes exactly ONE history row (old status,
-- new status, who, the note). The ticket row is locked first, so two people acting at the same moment are decided one
-- after the other: the second sees the new status and is refused if its move no longer fits (for example two people
-- resolving the same ticket). resolved_at is stamped on Resolved and cleared on a reopen; closed_at on Closed.
-- A staff user (p_visible_to is their id) can only change a ticket assigned to them; any other ticket is not found.
--   22023 invalid parameter - an unknown status, a note over 500 characters, or no note on open -> closed
--   P0002 not found         - unknown ticket or one outside p_visible_to
--   NX409 rule conflict     - a move that is not allowed (closed is final; reopen only from Resolved); a reopen
--                             while the customer has another active ticket (the message and HINT give its number)
CREATE OR REPLACE PROCEDURE sp_change_ticket_status(
    p_tenant_id integer, p_ticket_id bigint, p_new_status varchar, p_note varchar, p_user_id integer, p_visible_to integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_old_status  varchar;
    v_customer_id bigint;
    v_note        varchar := NULLIF(btrim(p_note), '');
BEGIN
    SELECT t.status INTO v_old_status
      FROM tickets t
     WHERE t.ticket_id = p_ticket_id AND t.tenant_id = p_tenant_id AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to)
       FOR UPDATE OF t;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ticket % not found', p_ticket_id USING ERRCODE = 'P0002';
    END IF;
    CALL sp_check_ticket_status_move(v_old_status, p_new_status, v_note);
    UPDATE tickets
       SET status = p_new_status,
           resolved_at = CASE p_new_status WHEN 'resolved' THEN now() WHEN 'closed' THEN resolved_at END,
           closed_at = CASE p_new_status WHEN 'closed' THEN now() END,
           updated_at = now()
     WHERE tickets.ticket_id = p_ticket_id AND tickets.tenant_id = p_tenant_id;
    INSERT INTO ticket_status_history (tenant_id, ticket_id, old_status, new_status, changed_by, note)
    VALUES (p_tenant_id, p_ticket_id, v_old_status, p_new_status, p_user_id, v_note);
EXCEPTION WHEN unique_violation THEN
    -- A reopen (resolved -> in_progress) while the customer has a newer active ticket: the unique index refuses it.
    -- The update was rolled back, so the customer's other active ticket is found and named.
    SELECT t.customer_id INTO v_customer_id FROM tickets t WHERE t.ticket_id = p_ticket_id AND t.tenant_id = p_tenant_id;
    CALL sp_assert_no_active_ticket(p_tenant_id, v_customer_id);
    RAISE;
END;
$$;
