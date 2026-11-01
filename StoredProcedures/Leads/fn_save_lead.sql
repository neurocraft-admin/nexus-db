-- Insert (p_lead_id NULL) or update a lead and return its id. The mobile is reduced to its stored form first, then
-- every duplicate check uses that form.
--   Insert: the lead starts as New, gets its LD number and a 'created' history row. A STAFF user (p_visible_to is
--           their id) always gets the lead assigned to themselves, whatever p_assigned_to says, so it does not vanish
--           from their view; an admin may name an assignee or leave it empty.
--   Update: changes the typed details only (sp_update_lead). Status, assignee and follow-up have their own
--           procedures, each with its own history row. A staff user can only update a lead assigned to them.
-- Errors (see also sp_check_lead_fields, sp_insert_lead and sp_update_lead):
--   NX409 rule conflict - another open lead has this mobile; the lead is deactivated; an inactive assignee
--   P0002 not found     - unknown lead, or a lead outside p_visible_to (indistinguishable); unknown assignee or source
CREATE OR REPLACE FUNCTION fn_save_lead(
    p_tenant_id integer, p_lead_id bigint, p_lead_name varchar, p_mobile varchar, p_email varchar, p_address varchar,
    p_lead_source_id integer, p_expected_value numeric, p_next_follow_up_date date, p_notes varchar,
    p_assigned_to integer, p_user_id integer, p_visible_to integer)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_mobile   varchar := fn_normalise_mobile(p_mobile);
    v_assignee integer := COALESCE(p_visible_to, p_assigned_to);
    v_saved    bigint;
BEGIN
    CALL sp_check_lead_fields(p_tenant_id, p_lead_name, v_mobile, p_email, p_address, p_lead_source_id, p_expected_value, p_notes);
    IF p_lead_id IS NOT NULL THEN
        CALL sp_update_lead(p_tenant_id, p_lead_id, p_lead_name, v_mobile, p_email, p_address, p_lead_source_id,
                            p_expected_value, p_next_follow_up_date, p_notes, p_visible_to);
        RETURN p_lead_id;
    END IF;
    IF v_assignee IS NOT NULL THEN
        CALL sp_assert_assignee(p_tenant_id, v_assignee);
    END IF;
    CALL sp_insert_lead(p_tenant_id, p_lead_name, v_mobile, p_email, p_address, p_lead_source_id, p_expected_value,
                        p_next_follow_up_date, p_notes, v_assignee, p_user_id, NULL, NULL, v_saved);
    RETURN v_saved;
END;
$$;
