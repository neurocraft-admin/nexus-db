-- Records which stored image is the hero picture of a DRAFT quotation (page 1), or clears it (both NULL). The image itself is a file in the API's
-- file folder, written once under a random name and never edited or deleted, so a quotation created from a template can share the template's file.
-- Only the stored name and the type (PNG or JPEG) are kept here.
--   22023 invalid parameter - a name without a type (or the reverse), or a type other than PNG or JPEG
--   P0002 not found         - an unknown quotation;  NX409 - the quotation is not a draft
CREATE OR REPLACE PROCEDURE sp_set_quotation_hero(p_tenant_id integer, p_quotation_id bigint, p_file_name varchar, p_content_type varchar)
LANGUAGE plpgsql AS $$
DECLARE
    v_status varchar;
BEGIN
    IF (p_file_name IS NULL) <> (p_content_type IS NULL) OR p_content_type NOT IN ('image/png', 'image/jpeg') THEN
        RAISE EXCEPTION 'A picture needs both a stored name and a type (PNG or JPEG)' USING ERRCODE = '22023', COLUMN = 'image';
    END IF;
    SELECT q.status INTO v_status FROM quotations q WHERE q.quotation_id = p_quotation_id AND q.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quotation % not found', p_quotation_id USING ERRCODE = 'P0002';
    END IF;
    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'Only a draft quotation can be edited; this one is %', v_status USING ERRCODE = 'NX409';
    END IF;
    UPDATE quotations SET hero_file_name = p_file_name, hero_content_type = p_content_type, updated_at = now()
     WHERE quotation_id = p_quotation_id AND tenant_id = p_tenant_id;
END;
$$;
