-- Applies the document settings JSON (p_document) to a quotation that sp_save_quotation has just written, then settles its subsidy
-- (sp_apply_subsidy). Called by sp_save_quotation inside its transaction. NULL means "no document settings in this save" (the old save path):
-- nothing but the subsidy invariant is touched. In an object, a key that is MISSING leaves that setting as it is and a key that is present
-- replaces it (null or blank clears a text). The keys: documentTitle, capacityKw, subsidyCategory, subsidyAmount, showLinePrices, costNotes,
-- paymentTermsHtml, termsHtml, datasheetIds (an ordered array of datasheet ids). See sp_check_document_settings for the rules.
-- p_prev_amount and p_prev_overridden: the subsidy the quotation had before this save (see sp_apply_subsidy).
DROP PROCEDURE IF EXISTS sp_apply_quotation_document(integer, bigint, jsonb);
CREATE OR REPLACE PROCEDURE sp_apply_quotation_document(
    p_tenant_id integer, p_quotation_id bigint, p_document jsonb, p_prev_amount numeric, p_prev_overridden boolean)
LANGUAGE plpgsql AS $$
DECLARE
    v_payable numeric;
    v_ids     bigint[];
BEGIN
    IF p_document IS NOT NULL THEN
        SELECT q.subtotal - q.extra_charges_amount - q.discount_amount INTO v_payable
          FROM quotations q WHERE q.quotation_id = p_quotation_id AND q.tenant_id = p_tenant_id;
        CALL sp_check_document_settings(p_tenant_id, p_document, v_payable);
        UPDATE quotations
           SET document_title = CASE WHEN p_document ? 'documentTitle' THEN NULLIF(btrim(p_document ->> 'documentTitle'), '') ELSE document_title END,
               show_line_prices = CASE WHEN jsonb_typeof(p_document -> 'showLinePrices') = 'boolean' THEN (p_document ->> 'showLinePrices')::boolean
                                       ELSE show_line_prices END,
               cost_notes = CASE WHEN p_document ? 'costNotes' THEN NULLIF(btrim(p_document ->> 'costNotes'), '') ELSE cost_notes END,
               payment_terms_html = CASE WHEN p_document ? 'paymentTermsHtml' THEN NULLIF(btrim(p_document ->> 'paymentTermsHtml'), '')
                                         ELSE payment_terms_html END,
               terms_html = CASE WHEN p_document ? 'termsHtml' THEN NULLIF(btrim(p_document ->> 'termsHtml'), '') ELSE terms_html END,
               updated_at = now()
         WHERE quotation_id = p_quotation_id AND tenant_id = p_tenant_id;
        IF p_document ? 'datasheetIds' THEN
            v_ids := ARRAY(SELECT x::bigint FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_document -> 'datasheetIds') = 'array'
                                                                               THEN p_document -> 'datasheetIds' ELSE '[]'::jsonb END) AS x);
            CALL sp_set_quotation_datasheets(p_tenant_id, p_quotation_id, v_ids);
        END IF;
    END IF;
    CALL sp_apply_subsidy(p_tenant_id, p_quotation_id, p_document, p_prev_amount, p_prev_overridden);
END;
$$;
