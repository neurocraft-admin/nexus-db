-- Applies the document settings JSON (p_document) to a template that sp_save_template has just written. Called inside its transaction. NULL means
-- no document settings in this save: nothing is changed. In an object, a key that is MISSING leaves that setting as it is and a key that is
-- present replaces it. The keys are the quotation's (see sp_apply_quotation_document) except subsidyAmount, which a template does not have: the
-- quotation works its subsidy out from the capacity and category when it is created.
CREATE OR REPLACE PROCEDURE sp_apply_template_document(p_tenant_id integer, p_template_id bigint, p_document jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    v_ids bigint[];
BEGIN
    IF p_document IS NULL THEN
        RETURN;
    END IF;
    CALL sp_check_document_settings(p_tenant_id, p_document, NULL);
    UPDATE quotation_templates
       SET document_title = CASE WHEN p_document ? 'documentTitle' THEN NULLIF(btrim(p_document ->> 'documentTitle'), '') ELSE document_title END,
           capacity_kw = CASE WHEN p_document ? 'capacityKw' THEN (p_document ->> 'capacityKw')::numeric ELSE capacity_kw END,
           subsidy_category = CASE WHEN p_document ? 'subsidyCategory' THEN COALESCE(p_document ->> 'subsidyCategory', 'none') ELSE subsidy_category END,
           show_line_prices = CASE WHEN jsonb_typeof(p_document -> 'showLinePrices') = 'boolean' THEN (p_document ->> 'showLinePrices')::boolean
                                   ELSE show_line_prices END,
           cost_notes = CASE WHEN p_document ? 'costNotes' THEN NULLIF(btrim(p_document ->> 'costNotes'), '') ELSE cost_notes END,
           payment_terms_html = CASE WHEN p_document ? 'paymentTermsHtml' THEN NULLIF(btrim(p_document ->> 'paymentTermsHtml'), '')
                                     ELSE payment_terms_html END,
           terms_html = CASE WHEN p_document ? 'termsHtml' THEN NULLIF(btrim(p_document ->> 'termsHtml'), '') ELSE terms_html END,
           updated_at = now()
     WHERE template_id = p_template_id AND tenant_id = p_tenant_id;
    IF p_document ? 'datasheetIds' THEN
        v_ids := ARRAY(SELECT x::bigint FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_document -> 'datasheetIds') = 'array'
                                                                           THEN p_document -> 'datasheetIds' ELSE '[]'::jsonb END) AS x);
        CALL sp_set_template_datasheets(p_tenant_id, p_template_id, v_ids);
    END IF;
END;
$$;
