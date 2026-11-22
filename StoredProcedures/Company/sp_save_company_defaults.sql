-- Saves the quotation fields added to the company profile after the first release: bankBranch, defaultPaymentTermsHtml, defaultTermsHtml and
-- defaultCostNotes. Called by sp_save_company_profile inside its transaction, after the row exists. A key that is NOT in the document leaves the
-- column as it is (so a caller that does not know these fields cannot wipe them); a key that is there, blank or not, replaces it.
CREATE OR REPLACE PROCEDURE sp_save_company_defaults(p_tenant_id integer, p_profile jsonb)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE company_profile
       SET bank_branch = CASE WHEN p_profile ? 'bankBranch' THEN fn_company_value(p_profile, 'bankBranch') ELSE bank_branch END,
           default_payment_terms_html = CASE WHEN p_profile ? 'defaultPaymentTermsHtml'
                                             THEN fn_company_value(p_profile, 'defaultPaymentTermsHtml') ELSE default_payment_terms_html END,
           default_terms_html = CASE WHEN p_profile ? 'defaultTermsHtml'
                                     THEN fn_company_value(p_profile, 'defaultTermsHtml') ELSE default_terms_html END,
           default_cost_notes = CASE WHEN p_profile ? 'defaultCostNotes'
                                     THEN fn_company_value(p_profile, 'defaultCostNotes') ELSE default_cost_notes END
     WHERE tenant_id = p_tenant_id;
END;
$$;
