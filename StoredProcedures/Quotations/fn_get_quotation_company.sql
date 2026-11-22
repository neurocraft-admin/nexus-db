-- The company details to print on a quotation: the SNAPSHOT frozen when it was sent, or, for a draft (or a quotation sent before snapshots existed),
-- the live company profile. from_snapshot says which. A snapshot is used exactly as it was frozen: a field that was empty then stays empty even if
-- the profile has it now. One row; no row when the quotation does not exist. Bank, tax ids and contacts are the structured profile fields.
CREATE OR REPLACE FUNCTION fn_get_quotation_company(p_tenant_id integer, p_quotation_id bigint)
RETURNS TABLE (from_snapshot boolean, legal_name varchar, display_name varchar, tagline varchar, logo_file_name varchar, logo_content_type varchar,
               address_line1 varchar, address_line2 varchar, city varchar, state_name varchar, pincode varchar, phone varchar, alternate_phone varchar,
               email varchar, website varchar, gstin varchar, pan varchar, state_code varchar, bank_account_name varchar, bank_name varchar,
               bank_account_number varchar, bank_ifsc varchar, bank_branch varchar, upi_id varchar)
LANGUAGE sql STABLE AS $$
    SELECT true, s."legalName", s."displayName", s.tagline, s."logoFileName", s."logoContentType", s."addressLine1", s."addressLine2", s.city,
           s."stateName", s.pincode, s.phone, s."alternatePhone", s.email, s.website, s.gstin, s.pan, s."stateCode", s."bankAccountName", s."bankName",
           s."bankAccountNumber", s."bankIfsc", s."bankBranch", s."upiId"
      FROM quotations q
     CROSS JOIN LATERAL jsonb_to_record(q.company_snapshot) AS s ("legalName" varchar, "displayName" varchar, tagline varchar, "logoFileName" varchar,
               "logoContentType" varchar, "addressLine1" varchar, "addressLine2" varchar, city varchar, "stateName" varchar, pincode varchar,
               phone varchar, "alternatePhone" varchar, email varchar, website varchar, gstin varchar, pan varchar, "stateCode" varchar,
               "bankAccountName" varchar, "bankName" varchar, "bankAccountNumber" varchar, "bankIfsc" varchar, "bankBranch" varchar, "upiId" varchar)
     WHERE q.tenant_id = p_tenant_id AND q.quotation_id = p_quotation_id AND q.company_snapshot IS NOT NULL
    UNION ALL
    SELECT false, c.legal_name, c.display_name, c.tagline, c.logo_file_name, c.logo_content_type, c.address_line1, c.address_line2, c.city,
           c.state_name, c.pincode, c.phone, c.alternate_phone, c.email, c.website, c.gstin, c.pan, c.state_code, c.bank_account_name, c.bank_name,
           c.bank_account_number, c.bank_ifsc, c.bank_branch, c.upi_id
      FROM quotations q
      LEFT JOIN company_profile c ON c.tenant_id = q.tenant_id
     WHERE q.tenant_id = p_tenant_id AND q.quotation_id = p_quotation_id AND q.company_snapshot IS NULL;
$$;
