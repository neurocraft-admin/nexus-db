-- Deactivates (hides) or reactivates a lead and writes exactly ONE history row. Nothing is ever deleted: a lead
-- entered by mistake is deactivated. A deactivated lead is not open, so it no longer blocks its mobile number;
-- reactivating an open lead is refused while another open lead has the number. Doing what is already the state
-- changes nothing and writes nothing. A staff user (p_visible_to is their id) can only change their own leads.
--   P0002 not found     - unknown lead or one outside p_visible_to
--   NX409 rule conflict - reactivating would duplicate an open lead's mobile
CREATE OR REPLACE PROCEDURE sp_set_lead_active(
    p_tenant_id integer, p_lead_id bigint, p_is_active boolean, p_user_id integer, p_visible_to integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_lead record;
BEGIN
    SELECT l.mobile, l.is_active, l.is_closed INTO v_lead FROM leads l
     WHERE l.lead_id = p_lead_id AND l.tenant_id = p_tenant_id AND (p_visible_to IS NULL OR l.assigned_to = p_visible_to)
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lead % not found', p_lead_id USING ERRCODE = 'P0002';
    END IF;
    IF v_lead.is_active = p_is_active THEN
        RETURN;
    END IF;
    IF p_is_active AND NOT v_lead.is_closed THEN
        CALL sp_assert_no_open_lead_mobile(p_tenant_id, v_lead.mobile, p_lead_id, p_visible_to);
    END IF;
    UPDATE leads SET is_active = p_is_active, updated_at = now() WHERE leads.lead_id = p_lead_id AND leads.tenant_id = p_tenant_id;
    CALL sp_log_lead_activity(p_tenant_id, p_lead_id, CASE WHEN p_is_active THEN 'reactivated' ELSE 'deactivated' END,
                              NULL, NULL, NULL, p_user_id);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'An open lead already has this mobile number' USING ERRCODE = 'NX409', COLUMN = 'mobile';
END;
$$;
