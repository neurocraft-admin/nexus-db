-- Adds a datasheet to the library (p_datasheet_id NULL: the API has already stored the PDF under p_stored_file_name) or renames / switches off an
-- existing one (only its name and active flag change: the file is never replaced, a new PDF is a new datasheet). Returns the id in p_saved_id.
-- Two ACTIVE datasheets cannot have the same name (letters and capitals do not matter); the check runs under a lock so two saves cannot both pass.
--   22023 invalid parameter - an empty or too long name, a missing file name or size on a new datasheet
--   P0002 not found         - an unknown datasheet
--   NX409 rule conflict     - another active datasheet has this name (COLUMN datasheetName)
CREATE OR REPLACE PROCEDURE sp_save_datasheet(
    p_tenant_id integer, p_datasheet_id bigint, p_name varchar, p_is_active boolean, p_stored_file_name varchar,
    p_original_file_name varchar, p_size_bytes integer, p_user_id integer, OUT p_saved_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_name varchar := btrim(p_name);
BEGIN
    IF v_name IS NULL OR v_name = '' OR length(v_name) > 150 THEN
        RAISE EXCEPTION 'Give the datasheet a name of up to 150 characters' USING ERRCODE = '22023', COLUMN = 'datasheetName';
    END IF;
    IF p_datasheet_id IS NULL AND (p_stored_file_name IS NULL OR btrim(p_original_file_name) = '' OR p_original_file_name IS NULL
                                   OR p_size_bytes IS NULL OR p_size_bytes <= 0) THEN
        RAISE EXCEPTION 'A new datasheet needs its PDF file' USING ERRCODE = '22023', COLUMN = 'file';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('datasheets:' || p_tenant_id, 0));
    IF p_datasheet_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM datasheets d WHERE d.datasheet_id = p_datasheet_id AND d.tenant_id = p_tenant_id) THEN
        RAISE EXCEPTION 'Datasheet % not found', p_datasheet_id USING ERRCODE = 'P0002';
    END IF;
    IF COALESCE(p_is_active, true) AND EXISTS (SELECT 1 FROM datasheets d WHERE d.tenant_id = p_tenant_id AND d.is_active
                                                AND lower(d.datasheet_name) = lower(v_name) AND d.datasheet_id IS DISTINCT FROM p_datasheet_id) THEN
        RAISE EXCEPTION 'A datasheet called % already exists', v_name USING ERRCODE = 'NX409', COLUMN = 'datasheetName';
    END IF;
    IF p_datasheet_id IS NULL THEN
        INSERT INTO datasheets (tenant_id, datasheet_name, stored_file_name, original_file_name, size_bytes, is_active, created_by)
        VALUES (p_tenant_id, v_name, p_stored_file_name, btrim(p_original_file_name), p_size_bytes, COALESCE(p_is_active, true), p_user_id)
        RETURNING datasheets.datasheet_id INTO p_saved_id;
    ELSE
        UPDATE datasheets SET datasheet_name = v_name, is_active = COALESCE(p_is_active, true), updated_at = now()
         WHERE datasheets.datasheet_id = p_datasheet_id AND datasheets.tenant_id = p_tenant_id
        RETURNING datasheets.datasheet_id INTO p_saved_id;
    END IF;
END;
$$;
