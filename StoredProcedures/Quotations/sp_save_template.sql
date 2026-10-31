-- One transaction: insert (p_template_id NULL) or update a quotation template and replace all its lines. Returns the
-- id in p_saved_id. p_lines is described in sp_check_document_lines; a line without a price takes the item's or
-- package's current price, and the price is then the template's own copy (it does not follow later price changes;
-- the screen shows a note when it differs from the current price). Templates can be deactivated (p_is_active).
--   22023 invalid parameter - validity not 1 to 365 days (COLUMN defaultValidityDays), or a line rule
--   23505 unique_violation  - another template has this name (case-insensitive, uq_quotation_templates_tenant_name)
--   P0002 not found         - unknown template, item or package
--   NX409 rule conflict     - an inactive item or package in the lines
-- The template row is locked first, so two saves of one template queue up instead of mixing their lines.
CREATE OR REPLACE PROCEDURE sp_save_template(
    p_tenant_id integer, p_template_id bigint, p_template_name varchar, p_description varchar,
    p_default_validity_days integer, p_terms_text varchar, p_is_active boolean, p_lines jsonb, OUT p_saved_id bigint)
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
                                          quantity, unit_price, sort_order)
    SELECT p_tenant_id, p_saved_id, n.line_type, n.item_id, n.package_id, n.description, n.unit, n.quantity,
           n.unit_price, n.sort_order
      FROM fn_normalise_document_lines(p_tenant_id, p_lines) n;
END;
$$;
