-- One package header with the same live figures as the list, active or not. Lines come from fn_get_package_lines.
CREATE OR REPLACE FUNCTION fn_get_package_by_id(p_tenant_id integer, p_package_id bigint)
RETURNS TABLE (package_id bigint, package_code varchar, package_name varchar, description varchar,
               package_price numeric, component_cost_at_save numeric, is_active boolean,
               component_count bigint, component_cost numeric, component_selling_total numeric,
               has_inactive_component boolean, short_component_count bigint, no_cost_component_count bigint)
LANGUAGE sql STABLE AS $$
    SELECT s.package_id, s.package_code, s.package_name, s.description, s.package_price,
           s.component_cost_at_save, s.is_active, s.component_count, s.component_cost,
           s.component_selling_total, s.has_inactive_component, s.short_component_count,
           s.no_cost_component_count
      FROM vw_package_summary s
     WHERE s.tenant_id = p_tenant_id
       AND s.package_id = p_package_id;
$$;
