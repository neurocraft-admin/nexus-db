-- Replaces the ordered datasheet list of a template (the order of p_ids is the order merged after the technical proposal). An empty list clears it.
-- Called by sp_save_template inside its transaction, or on its own by the API when only the list changes.
--   see sp_check_datasheet_ids; P0002 for an unknown template
CREATE OR REPLACE PROCEDURE sp_set_template_datasheets(p_tenant_id integer, p_template_id bigint, p_ids bigint[])
LANGUAGE plpgsql AS $$
DECLARE
    v_keep bigint[];
BEGIN
    PERFORM 1 FROM quotation_templates t WHERE t.template_id = p_template_id AND t.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Template % not found', p_template_id USING ERRCODE = 'P0002';
    END IF;
    v_keep := ARRAY(SELECT x.datasheet_id FROM template_datasheets x WHERE x.template_id = p_template_id);
    CALL sp_check_datasheet_ids(p_tenant_id, COALESCE(p_ids, ARRAY[]::bigint[]), v_keep);
    DELETE FROM template_datasheets WHERE template_id = p_template_id AND tenant_id = p_tenant_id;
    INSERT INTO template_datasheets (tenant_id, template_id, datasheet_id, sort_order)
    SELECT p_tenant_id, p_template_id, x.id, x.ord::integer FROM unnest(COALESCE(p_ids, ARRAY[]::bigint[])) WITH ORDINALITY AS x (id, ord);
END;
$$;
