-- p_password_hash is used only when creating; an existing password changes through
-- sp_reset_user_password or sp_change_password. Duplicate user names surface as 23505.
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
