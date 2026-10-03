-- The current state of one user, read on every authenticated API request so that deactivation, a changed
-- type and a changed role take effect on the next request (the JWT only says who the caller is).
-- is_active is the account's own flag; role_is_active is the role's. Kept in sync with 05_foundation_user_by_id.sql.
CREATE OR REPLACE FUNCTION fn_get_user_by_id(p_tenant_id integer, p_user_id integer)
RETURNS TABLE (user_id integer, user_name varchar, full_name varchar, role_id integer, role_name varchar,
               user_type varchar, must_change_password boolean, is_active boolean, role_is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT u.user_id, u.user_name, u.full_name, u.role_id, r.role_name,
           u.user_type, u.must_change_password, u.is_active, r.is_active
      FROM users u
      JOIN roles r ON r.role_id = u.role_id AND r.tenant_id = u.tenant_id
     WHERE u.tenant_id = p_tenant_id
       AND u.user_id = p_user_id;
$$;
