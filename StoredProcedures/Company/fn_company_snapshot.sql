-- The company details as they are printed on a quotation, as one JSON document: name, address, tax ids, contacts, bank and the stored logo name.
-- sp_set_quotation_status stores it on a quotation when it is SENT, so a reprint shows what the customer was sent even after the profile changes.
-- A company that has never saved a profile gives an object of nulls. The keys are camelCase and match fn_get_quotation_company.
CREATE OR REPLACE FUNCTION fn_company_snapshot(p_tenant_id integer)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
               'legalName', c.legal_name, 'displayName', c.display_name, 'tagline', c.tagline,
               'logoFileName', c.logo_file_name, 'logoContentType', c.logo_content_type,
               'addressLine1', c.address_line1, 'addressLine2', c.address_line2, 'city', c.city, 'stateName', c.state_name, 'pincode', c.pincode,
               'phone', c.phone, 'alternatePhone', c.alternate_phone, 'email', c.email, 'website', c.website,
               'gstin', c.gstin, 'pan', c.pan, 'stateCode', c.state_code,
               'bankAccountName', c.bank_account_name, 'bankName', c.bank_name, 'bankAccountNumber', c.bank_account_number,
               'bankIfsc', c.bank_ifsc, 'bankBranch', c.bank_branch, 'upiId', c.upi_id)
      FROM (SELECT p_tenant_id AS tenant_id) t
      LEFT JOIN company_profile c ON c.tenant_id = t.tenant_id;
$$;
