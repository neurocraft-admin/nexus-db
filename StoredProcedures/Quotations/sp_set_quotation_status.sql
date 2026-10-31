-- Moves a quotation to a new status, if the move is allowed, stamps the dates and writes the audit row.
--   draft -> sent        stamps sent_at; refused when valid_until is already past
--   draft -> rejected    "delete" of a draft: it stays on record
--   sent  -> approved    stamps decided_at; refused when valid_until is already past (it is an expired quotation)
--   sent  -> rejected    stamps decided_at
-- 'expired' is set only by sp_expire_quotations and 'converted' only by fn_convert_quotation_to_order, so they are
-- refused here like every other jump.
--   P0002 not found     - unknown quotation
--   NX409 rule conflict - a move that is not in the list, or an out-of-date valid_until (the message says which)
-- The row is locked first, so two people changing the same quotation queue up and the second sees the new status.
CREATE OR REPLACE PROCEDURE sp_set_quotation_status(
    p_tenant_id integer, p_quotation_id bigint, p_new_status varchar, p_changed_by integer, p_note varchar)
LANGUAGE plpgsql AS $$
DECLARE
    c_moves CONSTANT text[] := ARRAY['draft>sent', 'draft>rejected', 'sent>approved', 'sent>rejected'];
    v_old   varchar;
    v_valid date;
BEGIN
    SELECT q.status, q.valid_until INTO v_old, v_valid FROM quotations q
     WHERE q.quotation_id = p_quotation_id AND q.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quotation % not found', p_quotation_id USING ERRCODE = 'P0002';
    END IF;
    IF NOT (v_old || '>' || COALESCE(p_new_status, '')) = ANY (c_moves) THEN
        RAISE EXCEPTION 'A % quotation cannot be changed to %', v_old, p_new_status USING ERRCODE = 'NX409';
    END IF;
    IF p_new_status IN ('sent', 'approved') AND v_valid < fn_business_today(p_tenant_id) THEN
        RAISE EXCEPTION 'The valid-until date (%) has passed', v_valid USING ERRCODE = 'NX409', COLUMN = 'validUntil';
    END IF;
    UPDATE quotations
       SET status = p_new_status, updated_at = now(),
           sent_at = CASE WHEN p_new_status = 'sent' THEN now() ELSE sent_at END,
           decided_at = CASE WHEN p_new_status IN ('approved', 'rejected') THEN now() ELSE decided_at END
     WHERE quotation_id = p_quotation_id AND tenant_id = p_tenant_id;
    CALL sp_log_quotation_status(p_tenant_id, p_quotation_id, v_old, p_new_status, p_changed_by, p_note);
END;
$$;
