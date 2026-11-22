-- Records which stored image is the hero picture of a quotation template (the one a new quotation starts with), or clears it (both NULL). See
-- sp_set_quotation_hero: the file is written once under a random name and never deleted.
--   22023 invalid parameter - a name without a type (or the reverse), or a type other than PNG or JPEG;  P0002 - an unknown template
CREATE OR REPLACE PROCEDURE sp_set_template_hero(p_tenant_id integer, p_template_id bigint, p_file_name varchar, p_content_type varchar)
LANGUAGE plpgsql AS $$
BEGIN
    IF (p_file_name IS NULL) <> (p_content_type IS NULL) OR p_content_type NOT IN ('image/png', 'image/jpeg') THEN
        RAISE EXCEPTION 'A picture needs both a stored name and a type (PNG or JPEG)' USING ERRCODE = '22023', COLUMN = 'image';
    END IF;
    UPDATE quotation_templates SET hero_file_name = p_file_name, hero_content_type = p_content_type, updated_at = now()
     WHERE template_id = p_template_id AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Template % not found', p_template_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;
