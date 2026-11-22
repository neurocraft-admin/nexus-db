-- The datasheet library, by name. Inactive datasheets are listed only when asked for. used_in_templates and used_in_quotations count where each one
-- is in a list, so the screen can say what switching it off affects. The PDF itself is read by the API from its file folder (stored_file_name).
CREATE OR REPLACE FUNCTION fn_get_datasheets(p_tenant_id integer, p_include_inactive boolean)
RETURNS TABLE (datasheet_id bigint, datasheet_name varchar, stored_file_name varchar, original_file_name varchar, size_bytes integer,
               is_active boolean, created_by_name varchar, created_at timestamptz, used_in_templates bigint, used_in_quotations bigint)
LANGUAGE sql STABLE AS $$
    SELECT d.datasheet_id, d.datasheet_name, d.stored_file_name, d.original_file_name, d.size_bytes, d.is_active, u.full_name, d.created_at,
           (SELECT count(*) FROM template_datasheets t WHERE t.datasheet_id = d.datasheet_id),
           (SELECT count(*) FROM quotation_datasheets q WHERE q.datasheet_id = d.datasheet_id)
      FROM datasheets d
      LEFT JOIN users u ON u.user_id = d.created_by
     WHERE d.tenant_id = p_tenant_id AND (COALESCE(p_include_inactive, false) OR d.is_active)
     ORDER BY lower(d.datasheet_name), d.datasheet_id;
$$;
