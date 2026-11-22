-- The datasheets chosen for a template, in the order they are merged. is_active false marks one that has since been switched off.
CREATE OR REPLACE FUNCTION fn_get_template_datasheets(p_tenant_id integer, p_template_id bigint)
RETURNS TABLE (datasheet_id bigint, datasheet_name varchar, stored_file_name varchar, original_file_name varchar, size_bytes integer,
               is_active boolean, sort_order integer)
LANGUAGE sql STABLE AS $$
    SELECT d.datasheet_id, d.datasheet_name, d.stored_file_name, d.original_file_name, d.size_bytes, d.is_active, x.sort_order
      FROM template_datasheets x
      JOIN datasheets d ON d.datasheet_id = x.datasheet_id
     WHERE x.tenant_id = p_tenant_id AND x.template_id = p_template_id
     ORDER BY x.sort_order;
$$;
