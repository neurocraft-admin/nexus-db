-- Gives a ticket to an active user (staff or admin) and writes exactly ONE history row: the status stays as it is (old
-- and new status are the same) and assigned_to says who it went to. It does NOT move open to in progress: that is a
-- separate, explicit status change. Assigning to the person who already has it changes nothing and writes nothing.
-- A staff user (p_visible_to is their id) can only reassign a ticket that is assigned to them; once given away it is no
-- longer theirs to see. A closed ticket is final and cannot be assigned.
--   P0002 not found     - unknown ticket or one outside p_visible_to; unknown assignee (COLUMN assignedTo)
--   NX409 rule conflict - a closed ticket; a deactivated assignee (COLUMN assignedTo)
CREATE OR REPLACE PROCEDURE sp_assign_ticket(
    p_tenant_id integer, p_ticket_id bigint, p_assigned_to integer, p_user_id integer, p_visible_to integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_ticket record;
BEGIN
    SELECT t.status, t.assigned_to INTO v_ticket
      FROM tickets t
     WHERE t.ticket_id = p_ticket_id AND t.tenant_id = p_tenant_id AND (p_visible_to IS NULL OR t.assigned_to = p_visible_to)
       FOR UPDATE OF t;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ticket % not found', p_ticket_id USING ERRCODE = 'P0002';
    END IF;
    IF v_ticket.status = 'closed' THEN
        RAISE EXCEPTION 'A closed ticket cannot be assigned' USING ERRCODE = 'NX409', COLUMN = 'status';
    END IF;
    CALL sp_assert_ticket_assignee(p_tenant_id, p_assigned_to);
    IF v_ticket.assigned_to IS NOT DISTINCT FROM p_assigned_to THEN
        RETURN;
    END IF;
    UPDATE tickets SET assigned_to = p_assigned_to, updated_at = now()
     WHERE tickets.ticket_id = p_ticket_id AND tickets.tenant_id = p_tenant_id;
    INSERT INTO ticket_status_history (tenant_id, ticket_id, old_status, new_status, assigned_to, changed_by)
    VALUES (p_tenant_id, p_ticket_id, v_ticket.status, v_ticket.status, p_assigned_to, p_user_id);
END;
$$;
