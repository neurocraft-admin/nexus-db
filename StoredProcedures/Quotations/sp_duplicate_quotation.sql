-- Copies a quotation of any status into a new DRAFT (a revision): the same customer or lead, lines (with make text and extra-charge flag), the
-- package component rows, document settings (title, hero picture, capacity, subsidy, whether prices are shown, notes, payment terms, terms and
-- conditions) and datasheet list, dated today with the same validity period. The company snapshot is NOT copied: a draft reads the live profile
-- until it is sent. The source is recorded in revision_of_id and the status log. Returns the new id in p_new_id.
--   P0002 not found - an unknown quotation
CREATE OR REPLACE PROCEDURE sp_duplicate_quotation(
    p_tenant_id integer, p_quotation_id bigint, p_created_by integer, OUT p_new_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_src   record;
    v_today date := fn_business_today(p_tenant_id);
BEGIN
    SELECT q.quotation_id, q.quotation_no, q.customer_id, q.lead_id, q.template_id, q.quotation_date, q.valid_until,
           q.subtotal, q.extra_charges_amount, q.discount_amount, q.total_amount, q.terms_text, q.notes, q.document_title, q.hero_file_name,
           q.hero_content_type, q.capacity_kw, q.subsidy_category, q.subsidy_amount, q.subsidy_overridden, q.show_line_prices, q.cost_notes,
           q.payment_terms_html, q.terms_html INTO v_src
      FROM quotations q
     WHERE q.quotation_id = p_quotation_id AND q.tenant_id = p_tenant_id FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quotation % not found', p_quotation_id USING ERRCODE = 'P0002';
    END IF;
    INSERT INTO quotations (tenant_id, quotation_no, customer_id, lead_id, template_id, revision_of_id, quotation_date,
                            valid_until, subtotal, extra_charges_amount, discount_amount, total_amount, terms_text, notes, created_by,
                            document_title, hero_file_name, hero_content_type, capacity_kw, subsidy_category, subsidy_amount,
                            subsidy_overridden, show_line_prices, cost_notes, payment_terms_html, terms_html)
    VALUES (p_tenant_id, fn_next_document_no(p_tenant_id, 'QTN'), v_src.customer_id, v_src.lead_id, v_src.template_id,
            v_src.quotation_id, v_today, v_today + (v_src.valid_until - v_src.quotation_date), v_src.subtotal, v_src.extra_charges_amount,
            v_src.discount_amount, v_src.total_amount, v_src.terms_text, v_src.notes, p_created_by,
            v_src.document_title, v_src.hero_file_name, v_src.hero_content_type, v_src.capacity_kw, v_src.subsidy_category, v_src.subsidy_amount,
            v_src.subsidy_overridden, v_src.show_line_prices, v_src.cost_notes, v_src.payment_terms_html, v_src.terms_html)
    RETURNING quotations.quotation_id INTO p_new_id;
    CALL sp_copy_quotation_children(p_tenant_id, p_quotation_id, p_new_id);
    CALL sp_log_quotation_status(p_tenant_id, p_new_id, NULL, 'draft', p_created_by,
                                 'Duplicated from ' || v_src.quotation_no);
END;
$$;
