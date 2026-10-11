-- Returns every resource, with false flags where the role has no row yet, so the
-- permissions screen can always show the full grid.
CREATE OR REPLACE FUNCTION fn_get_role_permissions(p_tenant_id integer, p_role_id integer)
RETURNS TABLE (resource_id integer, resource_code varchar, display_name varchar,
               can_view boolean, can_create boolean, can_update boolean, can_delete boolean)
LANGUAGE sql STABLE AS $$
    SELECT x.resource_id, x.resource_code, x.display_name,
           COALESCE(rp.can_view, false), COALESCE(rp.can_create, false),
           COALESCE(rp.can_update, false), COALESCE(rp.can_delete, false)
      FROM resources x
      LEFT JOIN role_permissions rp
             ON rp.resource_id = x.resource_id AND rp.role_id = p_role_id AND rp.tenant_id = x.tenant_id
     WHERE x.tenant_id = p_tenant_id
       AND EXISTS (SELECT 1 FROM roles r WHERE r.role_id = p_role_id AND r.tenant_id = p_tenant_id)
     ORDER BY x.display_name;
$$;
