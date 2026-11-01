-- Writes a checked quotation: the header (insert, or update of the draft already locked by sp_save_quotation) and
-- all its lines, replaced. Only ever called by sp_save_quotation, inside its transaction: the lines are deleted
-- first, so if the insert fails everything rolls back and the old lines are still there.
CREATE OR REPLACE PROCEDURE sp_write_quotation(
    p_tenant_id integer, p_quotation_id bigint, p_customer_id bigint, p_lead_id bigint, p_template_id bigint,
    p_quotation_date date, p_valid_until date, p_subtotal numeric, p_discount_amount numeric, p_terms_text varchar,
    p_notes varchar, p_created_by integer, p_lines jsonb, OUT p_saved_id bigint)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_quotation_id IS NULL THEN
        INSERT INTO quotations (tenant_id, quotation_no, customer_id, lead_id, template_id, quotation_date, valid_until,
                                subtotal, discount_amount, total_amount, terms_text, notes, created_by)
        VALUES (p_tenant_id, fn_next_document_no(p_tenant_id, 'QTN'), p_customer_id, p_lead_id, p_template_id,
                p_quotation_date, p_valid_until, p_subtotal, p_discount_amount, p_subtotal - p_discount_amount,
                p_terms_text, p_notes, p_created_by)
        RETURNING quotations.quotation_id INTO p_saved_id;
        CALL sp_log_quotation_status(p_tenant_id, p_saved_id, NULL, 'draft', p_created_by, 'Created');
    ELSE
        UPDATE quotations
           SET customer_id = p_customer_id, lead_id = p_lead_id, template_id = p_template_id,
               quotation_date = p_quotation_date, valid_until = p_valid_until, subtotal = p_subtotal,
               discount_amount = p_discount_amount, total_amount = p_subtotal - p_discount_amount,
               terms_text = p_terms_text, notes = p_notes, updated_at = now()
         WHERE quotations.quotation_id = p_quotation_id AND quotations.tenant_id = p_tenant_id
        RETURNING quotations.quotation_id INTO p_saved_id;
        DELETE FROM quotation_lines WHERE quotation_id = p_saved_id AND tenant_id = p_tenant_id;
    END IF;
    INSERT INTO quotation_lines (tenant_id, quotation_id, line_type, item_id, package_id, description, unit,
                                 quantity, unit_price, line_total, sort_order)
    SELECT p_tenant_id, p_saved_id, n.line_type, n.item_id, n.package_id, n.description, n.unit,
           n.quantity, n.unit_price, n.line_total, n.sort_order
      FROM fn_normalise_document_lines(p_tenant_id, p_lines) n;
END;
$$;
