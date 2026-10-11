CREATE OR REPLACE FUNCTION fn_get_user_permissions(p_tenant_id integer, p_user_id integer)
RETURNS TABLE (resource_code varchar, can_view boolean, can_create boolean,
               can_update boolean, can_delete boolean)
LANGUAGE sql STABLE AS $$
    SELECT x.resource_code, rp.can_view, rp.can_create, rp.can_update, rp.can_delete
      FROM users u
      JOIN role_permissions rp ON rp.role_id = u.role_id AND rp.tenant_id = u.tenant_id
      JOIN resources x         ON x.resource_id = rp.resource_id
     WHERE u.tenant_id = p_tenant_id
       AND u.user_id = p_user_id
       AND u.is_active
     ORDER BY x.resource_code;
$$;
