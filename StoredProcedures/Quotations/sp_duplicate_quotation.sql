-- "Duplicate as new draft": copies a quotation of ANY status (header, discount, terms, notes and every line with its
-- own copied price) into a new draft with a new QTN number, and returns its id in p_new_id. The copy points back
-- at the original through revision_of_id, which is what the revision chain on the view page follows. The quotation
-- date is today (business time zone) and the copy keeps the original's validity period in days. Prices are NOT
-- refreshed: a revision starts from what was quoted. An inactive customer, item or package is carried over; the
-- copy cannot be saved again until the person replaces it.
--   P0002 not found - unknown quotation
CREATE OR REPLACE PROCEDURE sp_duplicate_quotation(
    p_tenant_id integer, p_quotation_id bigint, p_created_by integer, OUT p_new_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_src   quotations%ROWTYPE;
    v_today date := fn_business_today(p_tenant_id);
BEGIN
    SELECT q.* INTO v_src FROM quotations q
     WHERE q.quotation_id = p_quotation_id AND q.tenant_id = p_tenant_id FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quotation % not found', p_quotation_id USING ERRCODE = 'P0002';
    END IF;
    INSERT INTO quotations (tenant_id, quotation_no, customer_id, lead_id, template_id, revision_of_id, quotation_date,
                            valid_until, subtotal, discount_amount, total_amount, terms_text, notes, created_by)
    VALUES (p_tenant_id, fn_next_document_no(p_tenant_id, 'QTN'), v_src.customer_id, v_src.lead_id, v_src.template_id,
            v_src.quotation_id, v_today, v_today + (v_src.valid_until - v_src.quotation_date), v_src.subtotal,
            v_src.discount_amount, v_src.total_amount, v_src.terms_text, v_src.notes, p_created_by)
    RETURNING quotations.quotation_id INTO p_new_id;
    INSERT INTO quotation_lines (tenant_id, quotation_id, line_type, item_id, package_id, description, unit,
                                 quantity, unit_price, line_total, sort_order)
    SELECT l.tenant_id, p_new_id, l.line_type, l.item_id, l.package_id, l.description, l.unit,
           l.quantity, l.unit_price, l.line_total, l.sort_order
      FROM quotation_lines l WHERE l.quotation_id = p_quotation_id AND l.tenant_id = p_tenant_id;
    CALL sp_log_quotation_status(p_tenant_id, p_new_id, NULL, 'draft', p_created_by,
                                 'Duplicated from ' || v_src.quotation_no);
END;
$$;
