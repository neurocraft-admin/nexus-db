-- Package list with live figures from vw_package_summary. p_search matches the code or the name (case-insensitive,
-- plain text: no wildcards); p_active_only hides deactivated packages. Lines are not returned here.
CREATE OR REPLACE FUNCTION fn_get_packages(p_tenant_id integer, p_search varchar, p_active_only boolean)
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
       AND (NOT COALESCE(p_active_only, false) OR s.is_active)
       AND (COALESCE(btrim(p_search), '') = ''
            OR position(lower(btrim(p_search)) IN lower(s.package_code || ' ' || s.package_name)) > 0)
     ORDER BY s.package_name, s.package_id;
$$;
