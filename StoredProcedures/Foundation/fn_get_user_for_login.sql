DROP FUNCTION IF EXISTS fn_get_user_for_login(integer, varchar);

CREATE OR REPLACE FUNCTION fn_get_user_for_login(p_tenant_id integer, p_user_name varchar)
RETURNS TABLE (user_id integer, user_name varchar, full_name varchar, password_hash varchar,
               role_id integer, role_name varchar, user_type varchar,
               must_change_password boolean, failed_attempts integer,
               locked_until timestamptz, is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT u.user_id, u.user_name, u.full_name, u.password_hash,
           u.role_id, r.role_name, u.user_type,
           u.must_change_password, u.failed_attempts,
           u.locked_until, (u.is_active AND r.is_active)
      FROM users u
      JOIN roles r ON r.role_id = u.role_id AND r.tenant_id = u.tenant_id
     WHERE u.tenant_id = p_tenant_id
       AND lower(u.user_name) = lower(p_user_name);
$$;
