DROP FUNCTION IF EXISTS fn_get_users(integer);

CREATE OR REPLACE FUNCTION fn_get_users(p_tenant_id integer)
RETURNS TABLE (user_id integer, user_name varchar, full_name varchar, mobile varchar,
               role_id integer, role_name varchar, user_type varchar,
               must_change_password boolean, last_login_at timestamptz, is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT u.user_id, u.user_name, u.full_name, u.mobile,
           u.role_id, r.role_name, u.user_type,
           u.must_change_password, u.last_login_at, u.is_active
      FROM users u
      JOIN roles r ON r.role_id = u.role_id AND r.tenant_id = u.tenant_id
     WHERE u.tenant_id = p_tenant_id
     ORDER BY u.full_name;
$$;
