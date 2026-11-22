-- Copies the CHOSEN lines of a template into a new draft quotation for a customer (or lead) and returns its id.
-- p_include_line_ids are the template_line_ids to copy: this is the per-customer product choice, so a line left out
-- is not saved at all. The quotation date is today (business time zone), valid_until is today plus the template's
-- default validity, and the terms come from the template. Prices are the template line's own prices (copied, not
-- refreshed); a package or item that has become inactive stops the save with a conflict naming it, and the caller
-- unticks that line. Everything happens in one transaction through sp_save_quotation.
-- The quotation also starts with the template's document settings (title, capacity, subsidy category, whether line prices are shown, cost-page
-- notes, payment terms, terms and conditions, datasheet list and hero picture); its subsidy is the slab suggestion for the capacity, and
-- every one of them can be edited on the quotation afterwards. Lines keep their make text and extra-charge flag.
--   22023 invalid parameter - no lines chosen, or a line id that is not on this template (COLUMN includeLineIds)
--   P0002 not found         - unknown template, customer, item or package
--   NX409 rule conflict     - an inactive template, customer, item or package
CREATE OR REPLACE FUNCTION fn_create_quotation_from_template(
    p_tenant_id integer, p_template_id bigint, p_customer_id bigint, p_lead_id bigint,
    p_include_line_ids bigint[], p_created_by integer)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_template record;
    v_lines    jsonb;
    v_today    date := fn_business_today(p_tenant_id);
    v_id       bigint;
BEGIN
    SELECT t.default_validity_days, t.terms_text, t.is_active, t.hero_file_name, t.hero_content_type, t.document_title, t.capacity_kw,
           t.subsidy_category, t.show_line_prices, t.cost_notes, t.payment_terms_html, t.terms_html INTO v_template
      FROM quotation_templates t WHERE t.template_id = p_template_id AND t.tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Template % not found', p_template_id USING ERRCODE = 'P0002', COLUMN = 'templateId';
    END IF;
    IF NOT v_template.is_active THEN
        RAISE EXCEPTION 'Template % is inactive', p_template_id USING ERRCODE = 'NX409', COLUMN = 'templateId';
    END IF;
    IF p_include_line_ids IS NULL OR cardinality(p_include_line_ids) = 0 OR (
           SELECT count(*) FROM quotation_template_lines l
            WHERE l.tenant_id = p_tenant_id AND l.template_id = p_template_id
              AND l.template_line_id = ANY (p_include_line_ids))
         <> (SELECT count(DISTINCT x) FROM unnest(p_include_line_ids) AS x) THEN
        RAISE EXCEPTION 'Choose at least one line of this template' USING ERRCODE = '22023', COLUMN = 'includeLineIds';
    END IF;
    v_lines := fn_template_lines_json(p_tenant_id, p_template_id, p_include_line_ids);
    CALL sp_save_quotation(p_tenant_id, NULL, p_customer_id, p_lead_id, p_template_id, v_today,
                           v_today + v_template.default_validity_days, 0, v_template.terms_text, NULL, p_created_by,
                           v_lines, v_id, fn_template_document(p_tenant_id, p_template_id));
    IF v_template.hero_file_name IS NOT NULL THEN
        CALL sp_set_quotation_hero(p_tenant_id, v_id, v_template.hero_file_name, v_template.hero_content_type);
    END IF;
    RETURN v_id;
END;
$$;
