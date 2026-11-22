-- One transaction: insert (p_template_id NULL) or update a quotation template and replace all its lines. Line prices are the template's own
-- (copied onto a quotation when it is created from the template, not refreshed). p_lines is described in sp_check_document_lines (the same
-- shape as a quotation's: make text and the extra-charge flag included; "components" are accepted and ignored, a package's components are
-- copied when a QUOTATION is saved). Returns the id in p_saved_id.
-- p_document (optional, the LAST parameter so an older caller keeps working) carries the document settings: see sp_apply_template_document.
--   22023 invalid parameter - see sp_check_document_lines and the document settings rules; a default validity outside 1 to 365 days
--   P0002 not found         - unknown template, item, package, subsidy category or datasheet
--   NX409 rule conflict     - an inactive item, package or datasheet
DROP PROCEDURE IF EXISTS sp_save_template(integer, bigint, varchar, varchar, integer, varchar, boolean, jsonb, bigint);
CREATE OR REPLACE PROCEDURE sp_save_template(
    p_tenant_id integer, p_template_id bigint, p_template_name varchar, p_description varchar,
    p_default_validity_days integer, p_terms_text varchar, p_is_active boolean, p_lines jsonb, OUT p_saved_id bigint,
    p_document jsonb DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_default_validity_days IS NULL OR p_default_validity_days NOT BETWEEN 1 AND 365 THEN
        RAISE EXCEPTION 'The default validity must be 1 to 365 days' USING ERRCODE = '22023', COLUMN = 'defaultValidityDays';
    END IF;
    IF p_template_id IS NOT NULL THEN
        PERFORM 1 FROM quotation_templates t WHERE t.template_id = p_template_id AND t.tenant_id = p_tenant_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Template % not found', p_template_id USING ERRCODE = 'P0002';
        END IF;
    END IF;
    CALL sp_check_document_lines(p_lines);
    CALL sp_check_document_references(p_tenant_id, p_lines);
    IF p_template_id IS NULL THEN
        INSERT INTO quotation_templates (tenant_id, template_name, description, default_validity_days, terms_text, is_active)
        VALUES (p_tenant_id, p_template_name, p_description, p_default_validity_days, p_terms_text, COALESCE(p_is_active, true))
        RETURNING quotation_templates.template_id INTO p_saved_id;
    ELSE
        UPDATE quotation_templates
           SET template_name = p_template_name, description = p_description, default_validity_days = p_default_validity_days,
               terms_text = p_terms_text, is_active = COALESCE(p_is_active, true), updated_at = now()
         WHERE quotation_templates.template_id = p_template_id AND quotation_templates.tenant_id = p_tenant_id
        RETURNING quotation_templates.template_id INTO p_saved_id;
        DELETE FROM quotation_template_lines WHERE template_id = p_saved_id AND tenant_id = p_tenant_id;
    END IF;
    INSERT INTO quotation_template_lines (tenant_id, template_id, line_type, item_id, package_id, description, unit,
                                          quantity, unit_price, sort_order, make_text, is_extra_charge)
    SELECT p_tenant_id, p_saved_id, n.line_type, n.item_id, n.package_id, n.description, n.unit, n.quantity,
           n.unit_price, n.sort_order, n.make_text, n.is_extra_charge
      FROM fn_normalise_document_lines(p_tenant_id, p_lines) n;
    CALL sp_apply_template_document(p_tenant_id, p_saved_id, p_document);
END;
$$;
