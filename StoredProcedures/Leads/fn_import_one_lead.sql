-- Saves one imported row inside its own sub-transaction, so that if it fails only this row is rolled back. Returns ONE
-- row: new_lead_id is the lead's id when it was created (reject_reason is then NULL), otherwise new_lead_id is NULL and
-- reject_reason says why the row was rejected. Only the failures a bad row can cause are turned into a reason (a
-- duplicate mobile, a value out of range, a rule conflict, an unknown source); anything else is a real fault and is
-- raised, so it can never be mistaken for "a bad row".
DROP FUNCTION IF EXISTS fn_import_one_lead(integer, text, text, text, text, integer, numeric, date, text, integer, integer, bigint, text);
CREATE OR REPLACE FUNCTION fn_import_one_lead(
    p_tenant_id integer, p_lead_name text, p_mobile text, p_email text, p_address text, p_lead_source_id integer,
    p_expected_value numeric, p_next_follow_up_date date, p_notes text, p_assigned_to integer, p_user_id integer,
    p_batch_id bigint, p_activity_note text, p_visible_to integer)
RETURNS TABLE (new_lead_id bigint, reject_reason text)
LANGUAGE plpgsql AS $$
DECLARE
    v_id bigint;
BEGIN
    CALL sp_check_lead_fields(p_tenant_id, p_lead_name, p_mobile, p_email, p_address, p_lead_source_id, p_expected_value, p_notes);
    CALL sp_insert_lead(p_tenant_id, p_lead_name, p_mobile, p_email, p_address, p_lead_source_id, p_expected_value,
                        p_next_follow_up_date, p_notes, p_assigned_to, p_user_id, p_batch_id, p_activity_note, p_visible_to, v_id);
    RETURN QUERY SELECT v_id, NULL::text;
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE IN ('NX409', '23505', '22023', 'P0002', '22003') THEN
        RETURN QUERY SELECT NULL::bigint, SQLERRM::text;
    ELSE
        RAISE;
    END IF;
END;
$$;
