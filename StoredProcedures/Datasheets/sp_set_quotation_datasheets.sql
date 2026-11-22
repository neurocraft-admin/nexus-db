-- Replaces the ordered datasheet list of a DRAFT quotation (the order of p_ids is the order merged after the technical proposal). An empty list
-- clears it. Called by sp_save_quotation inside its transaction, or on its own by the API when only the list changes.
--   see sp_check_datasheet_ids; P0002 for an unknown quotation; NX409 when the quotation is not a draft
CREATE OR REPLACE PROCEDURE sp_set_quotation_datasheets(p_tenant_id integer, p_quotation_id bigint, p_ids bigint[])
LANGUAGE plpgsql AS $$
DECLARE
    v_status varchar;
    v_keep   bigint[];
BEGIN
    SELECT q.status INTO v_status FROM quotations q WHERE q.quotation_id = p_quotation_id AND q.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quotation % not found', p_quotation_id USING ERRCODE = 'P0002';
    END IF;
    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'Only a draft quotation can be edited; this one is %', v_status USING ERRCODE = 'NX409';
    END IF;
    v_keep := ARRAY(SELECT x.datasheet_id FROM quotation_datasheets x WHERE x.quotation_id = p_quotation_id);
    CALL sp_check_datasheet_ids(p_tenant_id, COALESCE(p_ids, ARRAY[]::bigint[]), v_keep);
    DELETE FROM quotation_datasheets WHERE quotation_id = p_quotation_id AND tenant_id = p_tenant_id;
    INSERT INTO quotation_datasheets (tenant_id, quotation_id, datasheet_id, sort_order)
    SELECT p_tenant_id, p_quotation_id, x.id, x.ord::integer FROM unnest(COALESCE(p_ids, ARRAY[]::bigint[])) WITH ORDINALITY AS x (id, ord);
END;
$$;
