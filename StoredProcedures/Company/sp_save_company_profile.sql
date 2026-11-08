-- Saves the company profile of one tenant from a JSON document (the request fields in camelCase), creating the row on the
-- first save. Every field is optional and a blank is stored as NULL. GSTIN, PAN and IFSC are stored upper-cased. The logo
-- has its own procedure (sp_set_company_logo) and is not touched here. One transaction: it saves all of it or none.
--   22023 invalid parameter - a field that does not fit its column or format (see sp_check_company_profile)
CREATE OR REPLACE PROCEDURE sp_save_company_profile(p_tenant_id integer, p_profile jsonb, p_user_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    CALL sp_check_company_profile(p_profile);
    INSERT INTO company_profile (tenant_id) VALUES (p_tenant_id) ON CONFLICT (tenant_id) DO NOTHING;
    UPDATE company_profile
       SET legal_name = fn_company_value(p_profile, 'legalName'),
           display_name = fn_company_value(p_profile, 'displayName'),
           tagline = fn_company_value(p_profile, 'tagline'),
           address_line1 = fn_company_value(p_profile, 'addressLine1'),
           address_line2 = fn_company_value(p_profile, 'addressLine2'),
           city = fn_company_value(p_profile, 'city'),
           state_name = fn_company_value(p_profile, 'stateName'),
           pincode = fn_company_value(p_profile, 'pincode'),
           phone = fn_company_value(p_profile, 'phone'),
           alternate_phone = fn_company_value(p_profile, 'alternatePhone'),
           email = fn_company_value(p_profile, 'email'),
           website = fn_company_value(p_profile, 'website'),
           gstin = upper(fn_company_value(p_profile, 'gstin')),
           pan = upper(fn_company_value(p_profile, 'pan')),
           state_code = fn_company_value(p_profile, 'stateCode'),
           bank_account_name = fn_company_value(p_profile, 'bankAccountName'),
           bank_name = fn_company_value(p_profile, 'bankName'),
           bank_account_number = fn_company_value(p_profile, 'bankAccountNumber'),
           bank_ifsc = upper(fn_company_value(p_profile, 'bankIfsc')),
           upi_id = fn_company_value(p_profile, 'upiId'),
           other_payment_details = fn_company_value(p_profile, 'otherPaymentDetails'),
           quotation_footer_note = fn_company_value(p_profile, 'quotationFooterNote'),
           quotation_terms = fn_company_value(p_profile, 'quotationTerms'),
           updated_by = p_user_id, updated_at = now()
     WHERE tenant_id = p_tenant_id;
END;
$$;
