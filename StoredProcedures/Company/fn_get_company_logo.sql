-- The stored name and type of the company logo, for serving the image (to the PDF and to the public portal). No row when
-- the tenant has no logo.
CREATE OR REPLACE FUNCTION fn_get_company_logo(p_tenant_id integer)
RETURNS TABLE (logo_file_name varchar, logo_content_type varchar)
LANGUAGE sql STABLE AS $$
    SELECT c.logo_file_name, c.logo_content_type
      FROM company_profile c
     WHERE c.tenant_id = p_tenant_id AND c.logo_file_name IS NOT NULL;
$$;
