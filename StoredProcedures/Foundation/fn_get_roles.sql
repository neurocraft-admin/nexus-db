CREATE OR REPLACE FUNCTION fn_get_roles(p_tenant_id integer)
RETURNS TABLE (role_id integer, role_name varchar, is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT r.role_id, r.role_name, r.is_active
      FROM roles r
     WHERE r.tenant_id = p_tenant_id
     ORDER BY r.role_name;
$$;
