-- The company profile of one tenant. ALWAYS returns exactly one row: a tenant that has never saved a profile gets a row of
-- NULLs (updated_at is NULL then), so the caller never has to handle "no profile". logo_file_name is the stored (random)
-- name, for the API's own use: it is never sent to a browser. updated_by_name says who saved it last.
CREATE OR REPLACE FUNCTION fn_get_company_profile(p_tenant_id integer)
RETURNS TABLE (legal_name varchar, display_name varchar, tagline varchar, logo_file_name varchar, logo_content_type varchar,
               address_line1 varchar, address_line2 varchar, city varchar, state_name varchar, pincode varchar,
               phone varchar, alternate_phone varchar, email varchar, website varchar, gstin varchar, pan varchar,
               state_code varchar, bank_account_name varchar, bank_name varchar, bank_account_number varchar,
               bank_ifsc varchar, upi_id varchar, other_payment_details varchar, quotation_footer_note varchar,
               quotation_terms varchar, updated_by_name varchar, updated_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT c.legal_name, c.display_name, c.tagline, c.logo_file_name, c.logo_content_type, c.address_line1,
           c.address_line2, c.city, c.state_name, c.pincode, c.phone, c.alternate_phone, c.email, c.website, c.gstin,
           c.pan, c.state_code, c.bank_account_name, c.bank_name, c.bank_account_number, c.bank_ifsc, c.upi_id,
           c.other_payment_details, c.quotation_footer_note, c.quotation_terms, u.full_name, c.updated_at
      FROM (SELECT p_tenant_id AS tenant_id) t
      LEFT JOIN company_profile c ON c.tenant_id = t.tenant_id
      LEFT JOIN users u ON u.user_id = c.updated_by;
$$;
