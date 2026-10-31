-- One transaction: insert (p_quotation_id NULL) or update a DRAFT quotation and replace all its lines. The server
-- works out every figure: line_total = round(quantity x unit_price, 2); subtotal = the sum of the line totals;
-- total = subtotal - discount. Returns the id in p_saved_id. A new quotation gets its QTN number here; the number
-- comes from a counter inside this transaction, so a failed save does not use one up. p_lines is described in
-- sp_check_document_lines. Prices are tax-inclusive and copied onto the quotation.
--   22023 invalid parameter - see sp_check_quotation_header and sp_check_document_lines; also a discount above the
--                             subtotal (COLUMN discountAmount)
--   P0002 not found         - unknown quotation, customer, template, item or package
--   NX409 rule conflict     - the quotation is not a draft; an inactive customer, item or package
-- The quotation row is locked first, so two saves of one draft queue up instead of mixing their lines.
CREATE OR REPLACE PROCEDURE sp_save_quotation(
    p_tenant_id integer, p_quotation_id bigint, p_customer_id bigint, p_lead_id bigint, p_template_id bigint,
    p_quotation_date date, p_valid_until date, p_discount_amount numeric, p_terms_text varchar, p_notes varchar,
    p_created_by integer, p_lines jsonb, OUT p_saved_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_status   varchar;
    v_subtotal numeric;
BEGIN
    IF p_quotation_id IS NOT NULL THEN
        SELECT q.status INTO v_status FROM quotations q
         WHERE q.quotation_id = p_quotation_id AND q.tenant_id = p_tenant_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Quotation % not found', p_quotation_id USING ERRCODE = 'P0002';
        END IF;
        IF v_status <> 'draft' THEN
            RAISE EXCEPTION 'Only a draft quotation can be edited; this one is %', v_status USING ERRCODE = 'NX409';
        END IF;
    END IF;
    CALL sp_check_quotation_header(p_tenant_id, p_customer_id, p_lead_id, p_template_id, p_quotation_date,
                                   p_valid_until, p_discount_amount);
    CALL sp_check_document_lines(p_lines);
    CALL sp_check_document_references(p_tenant_id, p_lines);
    SELECT COALESCE(sum(n.line_total), 0) INTO v_subtotal FROM fn_normalise_document_lines(p_tenant_id, p_lines) n;
    IF p_discount_amount > v_subtotal THEN
        RAISE EXCEPTION 'The discount cannot be more than the subtotal' USING ERRCODE = '22023', COLUMN = 'discountAmount';
    END IF;
    CALL sp_write_quotation(p_tenant_id, p_quotation_id, p_customer_id, p_lead_id, p_template_id, p_quotation_date,
                            p_valid_until, v_subtotal, p_discount_amount, p_terms_text, p_notes, p_created_by,
                            p_lines, p_saved_id);
END;
$$;
