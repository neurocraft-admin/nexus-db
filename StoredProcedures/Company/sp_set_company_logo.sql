-- Records which file is the company logo, or clears it (p_file_name NULL), and hands back the file that was the logo
-- before so the API can delete it from disk. The profile row is created if it does not exist yet. The file itself lives
-- under Company:LogoPath; this only keeps its random stored name and its type.
-- A logo that a SENT quotation's company snapshot still points at is NOT handed back (p_previous_file_name is NULL then), so the API keeps the file
-- and a reprint of that quotation still shows the logo it was sent with.
--   22023 invalid parameter - a name without a type (or the reverse), or a type other than PNG or JPEG
CREATE OR REPLACE PROCEDURE sp_set_company_logo(
    p_tenant_id integer, p_file_name varchar, p_content_type varchar, p_user_id integer, OUT p_previous_file_name varchar)
LANGUAGE plpgsql AS $$
BEGIN
    IF (p_file_name IS NULL) <> (p_content_type IS NULL) OR p_content_type NOT IN ('image/png', 'image/jpeg') THEN
        RAISE EXCEPTION 'A logo needs both a stored name and a type (PNG or JPEG)' USING ERRCODE = '22023', COLUMN = 'logo';
    END IF;
    INSERT INTO company_profile (tenant_id) VALUES (p_tenant_id) ON CONFLICT (tenant_id) DO NOTHING;
    SELECT c.logo_file_name INTO p_previous_file_name FROM company_profile c WHERE c.tenant_id = p_tenant_id FOR UPDATE;
    UPDATE company_profile
       SET logo_file_name = p_file_name, logo_content_type = p_content_type, updated_by = p_user_id, updated_at = now()
     WHERE tenant_id = p_tenant_id;
    IF p_previous_file_name IS NOT NULL AND EXISTS (
           SELECT 1 FROM quotations q WHERE q.tenant_id = p_tenant_id AND q.company_snapshot ->> 'logoFileName' = p_previous_file_name) THEN
        p_previous_file_name := NULL;
    END IF;
END;
$$;
