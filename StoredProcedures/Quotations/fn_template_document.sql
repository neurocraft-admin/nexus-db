-- The document settings of a template as the JSON that sp_save_quotation reads (documentTitle, capacityKw, subsidyCategory, showLinePrices,
-- costNotes, paymentTermsHtml, termsHtml and the ordered datasheetIds), so a quotation created from the template starts with them.
-- A datasheet that has been switched off since is left out of the list. subsidyAmount is left out on purpose: the quotation works its subsidy out from the capacity and category.
CREATE OR REPLACE FUNCTION fn_template_document(p_tenant_id integer, p_template_id bigint)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
               'documentTitle', t.document_title, 'capacityKw', t.capacity_kw, 'subsidyCategory', t.subsidy_category,
               'showLinePrices', t.show_line_prices, 'costNotes', t.cost_notes, 'paymentTermsHtml', t.payment_terms_html,
               'termsHtml', t.terms_html,
               'datasheetIds', COALESCE((SELECT jsonb_agg(d.datasheet_id ORDER BY d.sort_order) FROM template_datasheets d
                                          JOIN datasheets s ON s.datasheet_id = d.datasheet_id AND s.is_active
                                         WHERE d.template_id = t.template_id AND d.tenant_id = t.tenant_id), '[]'::jsonb))
      FROM quotation_templates t
     WHERE t.tenant_id = p_tenant_id AND t.template_id = p_template_id;
$$;
