-- Raises NX409 when an edit would leave the system with no active admin: the user being edited is the
-- last active admin and the edit moves them off type 'admin' or off the Admin role.
-- fn_set_user_active guards deactivation; this guards demotion. Kept in sync with 04_foundation_last_admin_guard.sql.
CREATE OR REPLACE FUNCTION fn_check_admin_demotion(
    p_tenant_id integer, p_user_id integer, p_new_user_type varchar, p_new_role_id integer)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    c_admin_type  CONSTANT varchar := 'admin';
    c_admin_role  CONSTANT varchar := 'Admin';
    v_old_type     varchar;
    v_is_active    boolean;
    v_new_role     varchar;
    v_other_admins integer;
BEGIN
    SELECT u.user_type, u.is_active INTO v_old_type, v_is_active
      FROM users u
     WHERE u.user_id = p_user_id AND u.tenant_id = p_tenant_id
       FOR UPDATE;
    IF NOT FOUND OR v_old_type <> c_admin_type OR NOT v_is_active THEN
        RETURN;
    END IF;

    SELECT r.role_name INTO v_new_role
      FROM roles r WHERE r.role_id = p_new_role_id AND r.tenant_id = p_tenant_id;
    IF p_new_user_type = c_admin_type AND v_new_role = c_admin_role THEN
        RETURN;   -- still a full admin, nothing is lost
    END IF;

    -- Lock the other admins so two simultaneous demotions cannot both pass the check.
    SELECT count(*) INTO v_other_admins FROM (
        SELECT u.user_id FROM users u
         WHERE u.tenant_id = p_tenant_id AND u.user_type = c_admin_type
           AND u.is_active AND u.user_id <> p_user_id
           FOR UPDATE) a;
    IF v_other_admins = 0 THEN
        RAISE EXCEPTION 'Cannot demote the last active admin' USING ERRCODE = 'NX409';
    END IF;
END;
$$;
