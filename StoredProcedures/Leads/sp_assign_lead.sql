-- Gives a lead to an active user and writes exactly ONE 'assigned' history row (the old and new person's name).
-- Assigning to the person who already has it changes nothing and writes nothing. A staff user (p_visible_to is
-- their id) can only reassign a lead that is assigned to them; once given away it is no longer theirs to see.
--   P0002 not found     - unknown lead or one outside p_visible_to; unknown assignee (COLUMN assignedTo)
--   NX409 rule conflict - a deactivated lead or assignee
CREATE OR REPLACE PROCEDURE sp_assign_lead(
    p_tenant_id integer, p_lead_id bigint, p_assigned_to integer, p_user_id integer, p_visible_to integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_lead     record;
    v_new_name varchar;
BEGIN
    SELECT l.assigned_to, l.is_active, u.full_name INTO v_lead
      FROM leads l LEFT JOIN users u ON u.user_id = l.assigned_to
     WHERE l.lead_id = p_lead_id AND l.tenant_id = p_tenant_id AND (p_visible_to IS NULL OR l.assigned_to = p_visible_to)
       FOR UPDATE OF l;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lead % not found', p_lead_id USING ERRCODE = 'P0002';
    END IF;
    IF NOT v_lead.is_active THEN
        RAISE EXCEPTION 'A deactivated lead cannot be assigned' USING ERRCODE = 'NX409';
    END IF;
    CALL sp_assert_assignee(p_tenant_id, p_assigned_to);
    IF v_lead.assigned_to IS NOT DISTINCT FROM p_assigned_to THEN
        RETURN;
    END IF;
    SELECT u.full_name INTO v_new_name FROM users u WHERE u.user_id = p_assigned_to AND u.tenant_id = p_tenant_id;
    UPDATE leads SET assigned_to = p_assigned_to, updated_at = now() WHERE leads.lead_id = p_lead_id AND leads.tenant_id = p_tenant_id;
    CALL sp_log_lead_activity(p_tenant_id, p_lead_id, 'assigned', v_lead.full_name, v_new_name, NULL, p_user_id);
END;
$$;
