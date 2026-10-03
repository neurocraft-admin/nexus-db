-- Last-admin guard for edits: an edit may not demote the last active admin (NX409).
-- Re-runnable (CREATE OR REPLACE; no return columns change). The same definitions live in
-- StoredProcedures/Foundation/fn_check_admin_demotion.sql and fn_save_user.sql - keep them in sync.

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

CREATE OR REPLACE FUNCTION fn_save_user(
    p_tenant_id integer, p_user_id integer,
    p_user_name varchar, p_full_name varchar, p_mobile varchar,
    p_role_id integer, p_user_type varchar, p_password_hash varchar)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    v_user_id integer;
BEGIN
    PERFORM 1 FROM roles r WHERE r.role_id = p_role_id AND r.tenant_id = p_tenant_id AND r.is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Role % not found', p_role_id USING ERRCODE = 'P0002';
    END IF;

    IF p_user_id IS NULL THEN
        INSERT INTO users (tenant_id, user_name, full_name, mobile, password_hash, role_id, user_type)
        VALUES (p_tenant_id, p_user_name, p_full_name, p_mobile, p_password_hash, p_role_id, p_user_type)
        RETURNING users.user_id INTO v_user_id;
    ELSE
        PERFORM fn_check_admin_demotion(p_tenant_id, p_user_id, p_user_type, p_role_id);
        UPDATE users
           SET user_name = p_user_name, full_name = p_full_name, mobile = p_mobile,
               role_id = p_role_id, user_type = p_user_type, updated_at = now()
         WHERE users.user_id = p_user_id AND users.tenant_id = p_tenant_id
        RETURNING users.user_id INTO v_user_id;

        IF v_user_id IS NULL THEN
            RAISE EXCEPTION 'User % not found', p_user_id USING ERRCODE = 'P0002';
        END IF;
    END IF;
    RETURN v_user_id;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('04_foundation_last_admin_guard.sql')
ON CONFLICT DO NOTHING;
