-- One datasheet of the library (the API uses it to find the file on disk for a download).
CREATE OR REPLACE FUNCTION fn_get_datasheet_by_id(p_tenant_id integer, p_datasheet_id bigint)
RETURNS TABLE (datasheet_id bigint, datasheet_name varchar, stored_file_name varchar, original_file_name varchar, size_bytes integer,
               is_active boolean, created_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT d.datasheet_id, d.datasheet_name, d.stored_file_name, d.original_file_name, d.size_bytes, d.is_active, d.created_at
      FROM datasheets d
     WHERE d.tenant_id = p_tenant_id AND d.datasheet_id = p_datasheet_id;
$$;
