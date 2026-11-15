-- What the PUBLIC support portal may know about the business: the name to show (the display name, else the legal name,
-- else NULL) and whether there is a logo. NOTHING else is returned, on purpose: no tagline, address, contacts, tax ids,
-- bank or payment details. Always one row. Keep this the only function an anonymous endpoint reads for the company.
CREATE OR REPLACE FUNCTION fn_get_public_company(p_tenant_id integer)
RETURNS TABLE (display_name varchar, has_logo boolean)
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(c.display_name, c.legal_name)::varchar, COALESCE(c.logo_file_name IS NOT NULL, false)
      FROM (SELECT p_tenant_id AS tenant_id) t
      LEFT JOIN company_profile c ON c.tenant_id = t.tenant_id;
$$;
