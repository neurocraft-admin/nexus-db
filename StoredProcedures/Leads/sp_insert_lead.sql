-- Inserts one new lead and its 'created' history row, and returns the id in p_lead_id. Shared by fn_save_lead (a lead
-- typed in) and fn_import_leads (one row of a file), so both follow the same rules. The lead starts in the first
-- active status that is neither Won nor Lost (New). Everything has already been checked by sp_check_lead_fields and
-- p_mobile is in the stored form. The lead number comes from a counter inside this transaction, so a failed insert
-- does not use one up.
--   NX409 rule conflict - another open lead has this mobile number (also when two people save at the same moment:
--                         the unique index decides and the loser gets this same answer)
CREATE OR REPLACE PROCEDURE sp_insert_lead(
    p_tenant_id integer, p_lead_name varchar, p_mobile varchar, p_email varchar, p_address varchar,
    p_lead_source_id integer, p_expected_value numeric, p_next_follow_up_date date, p_notes varchar,
    p_assigned_to integer, p_user_id integer, p_import_batch_id bigint, p_activity_note varchar, OUT p_lead_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_status_id integer;
BEGIN
    SELECT s.lead_status_id INTO v_status_id FROM lead_statuses s
     WHERE s.tenant_id = p_tenant_id AND s.is_active AND NOT s.is_won AND NOT s.is_lost
     ORDER BY s.sort_order, s.lead_status_id LIMIT 1;
    IF v_status_id IS NULL THEN
        RAISE EXCEPTION 'No starting status is configured for leads' USING ERRCODE = 'NX409';
    END IF;
    CALL sp_assert_no_open_lead_mobile(p_tenant_id, p_mobile, NULL);
    INSERT INTO leads (tenant_id, lead_no, lead_name, mobile, email, address, lead_source_id, lead_status_id, assigned_to,
                       expected_value, next_follow_up_date, notes, import_batch_id, created_by)
    VALUES (p_tenant_id, fn_next_document_no(p_tenant_id, 'LD'), btrim(p_lead_name), p_mobile, p_email, p_address,
            p_lead_source_id, v_status_id, p_assigned_to, p_expected_value, p_next_follow_up_date, p_notes,
            p_import_batch_id, p_user_id)
    RETURNING leads.lead_id INTO p_lead_id;
    CALL sp_log_lead_activity(p_tenant_id, p_lead_id, 'created', NULL, NULL, p_activity_note, p_user_id);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'An open lead already has this mobile number' USING ERRCODE = 'NX409', COLUMN = 'mobile';
END;
$$;
