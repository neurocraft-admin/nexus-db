-- Imports the acceptable rows of a file and reports every row. One bad row never blocks the good ones: each row is
-- saved on its own (its own sub-transaction), so a row that fails is rolled back alone and reported with its reason.
-- The rows are validated again here, at the moment of import (fn_check_import_rows), whatever a preview said. Every
-- imported lead is entered exactly as a typed one is (sp_insert_lead): status New, an LD number, a 'created' history
-- row noting the file, and the same one-open-lead-per-mobile rule, which also decides a race with someone else
-- saving the same number. An import batch row records who imported which file and the counts.
-- Assignee: a STAFF user (p_visible_to is their id) gets every imported lead assigned to themselves; an admin may
-- give p_assigned_to for the whole file, or none.
-- outcome is 'created' or 'rejected'; warning may say the mobile already belongs to a customer.
--   22023 invalid parameter - see fn_check_import_rows; an empty file name (COLUMN fileName)
--   P0002 / NX409           - an unknown or deactivated assignee (COLUMN assignedTo)
CREATE OR REPLACE FUNCTION fn_import_leads(
    p_tenant_id integer, p_rows jsonb, p_file_name varchar, p_default_source_id integer, p_assigned_to integer,
    p_user_id integer, p_visible_to integer)
RETURNS TABLE (row_number integer, outcome text, lead_id bigint, lead_no text, reason text, warning text)
LANGUAGE plpgsql AS $$
DECLARE
    v_assignee integer := COALESCE(p_visible_to, p_assigned_to);
    v_batch    bigint;
    v_row      record;
    v_new      bigint;
    v_reason   text;
    v_created  integer := 0;
    v_total    integer := 0;
BEGIN
    IF p_file_name IS NULL OR btrim(p_file_name) = '' OR length(p_file_name) > 255 THEN
        RAISE EXCEPTION 'The import needs a file name of up to 255 characters' USING ERRCODE = '22023', COLUMN = 'fileName';
    END IF;
    CALL sp_assert_import_default_source(p_tenant_id, p_default_source_id);
    IF v_assignee IS NOT NULL THEN
        CALL sp_assert_assignee(p_tenant_id, v_assignee);
    END IF;
    INSERT INTO lead_import_batches (tenant_id, file_name, default_source_id, assigned_to, created_by)
    VALUES (p_tenant_id, btrim(p_file_name), p_default_source_id, v_assignee, p_user_id) RETURNING batch_id INTO v_batch;
    FOR v_row IN SELECT * FROM fn_check_import_rows(p_tenant_id, p_rows, p_default_source_id) ORDER BY 1 LOOP
        v_reason := v_row.reason; v_new := NULL;
        IF v_reason IS NULL THEN
            SELECT o.new_lead_id, o.reject_reason INTO v_new, v_reason
              FROM fn_import_one_lead(p_tenant_id, v_row.lead_name, v_row.mobile, v_row.email, v_row.address, v_row.lead_source_id,
                                      v_row.expected_value, v_row.next_follow_up_date, v_row.notes, v_assignee, p_user_id, v_batch,
                                      'Imported from ' || btrim(p_file_name)) o;
        END IF;
        v_created := v_created + CASE WHEN v_new IS NOT NULL THEN 1 ELSE 0 END;
        v_total := v_total + 1;
        RETURN QUERY SELECT v_row.row_number, CASE WHEN v_new IS NULL THEN 'rejected' ELSE 'created' END, v_new,
                            (SELECT l.lead_no::text FROM leads l WHERE l.lead_id = v_new), v_reason, v_row.warning;
    END LOOP;
    UPDATE lead_import_batches SET total_rows = v_total, created_rows = v_created, rejected_rows = v_total - v_created
     WHERE batch_id = v_batch;
END;
$$;
