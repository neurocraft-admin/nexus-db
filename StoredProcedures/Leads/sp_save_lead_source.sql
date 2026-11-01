-- Insert (p_lead_source_id NULL) or update a lead source and return its id in p_saved_id. This is the convenience
-- behind the source maintenance endpoints; the table stays the source of truth and a source can equally be added by
-- script. A source in use can be deactivated: its leads keep it and it leaves the dropdown.
--   22023 invalid parameter - empty or too long name (COLUMN sourceName), a code that is not lower-case letters,
--                             digits and underscores (COLUMN sourceCode)
--   23505 unique_violation  - another source has this name (ignoring case) or this code
--   P0002 not found         - unknown source on update
CREATE OR REPLACE PROCEDURE sp_save_lead_source(
    p_tenant_id integer, p_lead_source_id integer, p_source_name varchar, p_source_code varchar,
    p_sort_order integer, p_is_active boolean, OUT p_saved_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_source_name IS NULL OR btrim(p_source_name) = '' OR length(btrim(p_source_name)) > 100 THEN
        RAISE EXCEPTION 'A source needs a name of up to 100 characters' USING ERRCODE = '22023', COLUMN = 'sourceName';
    END IF;
    IF p_source_code IS NOT NULL AND p_source_code !~ '^[a-z][a-z0-9_]{0,29}$' THEN
        RAISE EXCEPTION 'The code is lower-case letters, digits and underscores, up to 30' USING ERRCODE = '22023', COLUMN = 'sourceCode';
    END IF;
    IF p_lead_source_id IS NULL THEN
        INSERT INTO lead_sources (tenant_id, source_name, source_code, sort_order, is_active)
        VALUES (p_tenant_id, btrim(p_source_name), p_source_code, COALESCE(p_sort_order, 0), COALESCE(p_is_active, true))
        RETURNING lead_sources.lead_source_id INTO p_saved_id;
    ELSE
        UPDATE lead_sources
           SET source_name = btrim(p_source_name), source_code = p_source_code, sort_order = COALESCE(p_sort_order, sort_order),
               is_active = COALESCE(p_is_active, is_active), updated_at = now()
         WHERE lead_sources.lead_source_id = p_lead_source_id AND lead_sources.tenant_id = p_tenant_id
        RETURNING lead_sources.lead_source_id INTO p_saved_id;
        IF p_saved_id IS NULL THEN
            RAISE EXCEPTION 'Lead source % not found', p_lead_source_id USING ERRCODE = 'P0002';
        END IF;
    END IF;
END;
$$;
