-- Updates the typed details of an existing lead (fn_save_lead's update path); status, assignee and follow-up have their
-- own procedures and history rows. p_mobile is in the stored form. A staff user (p_visible_to is their id) can only
-- update a lead assigned to them. Changing the mobile of an open lead is refused while another open lead has the
-- new number.
--   P0002 not found     - unknown lead, or one outside p_visible_to (indistinguishable)
--   NX409 rule conflict - a deactivated lead; another open lead has the new mobile
CREATE OR REPLACE PROCEDURE sp_update_lead(
    p_tenant_id integer, p_lead_id bigint, p_lead_name varchar, p_mobile varchar, p_email varchar, p_address varchar,
    p_lead_source_id integer, p_expected_value numeric, p_next_follow_up_date date, p_notes varchar, p_visible_to integer)
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
    IF NOT v_lead.is_active THEN
        RAISE EXCEPTION 'A deactivated lead cannot be edited' USING ERRCODE = 'NX409';
    END IF;
    IF NOT v_lead.is_closed AND v_lead.mobile <> p_mobile THEN
        CALL sp_assert_no_open_lead_mobile(p_tenant_id, p_mobile, p_lead_id, p_visible_to);
    END IF;
    UPDATE leads SET lead_name = btrim(p_lead_name), mobile = p_mobile, email = p_email, address = p_address,
           lead_source_id = p_lead_source_id, expected_value = p_expected_value, next_follow_up_date = p_next_follow_up_date,
           notes = p_notes, updated_at = now()
     WHERE leads.lead_id = p_lead_id AND leads.tenant_id = p_tenant_id;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'An open lead already has this mobile number' USING ERRCODE = 'NX409', COLUMN = 'mobile';
END;
$$;
