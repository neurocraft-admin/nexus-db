-- NX409 is our own SQLSTATE for "rule conflict"; the API maps it to 409.
CREATE OR REPLACE FUNCTION fn_set_user_active(p_tenant_id integer, p_user_id integer, p_is_active boolean)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_user_type  varchar;
    v_other_admins integer;
BEGIN
    SELECT u.user_type INTO v_user_type FROM users u
     WHERE u.user_id = p_user_id AND u.tenant_id = p_tenant_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found', p_user_id USING ERRCODE = 'P0002';
    END IF;

    IF NOT p_is_active AND v_user_type = 'admin' THEN
        -- Lock the other admins so two simultaneous deactivations cannot both pass the check.
        SELECT count(*) INTO v_other_admins FROM (
            SELECT u.user_id FROM users u
             WHERE u.tenant_id = p_tenant_id AND u.user_type = 'admin'
               AND u.is_active AND u.user_id <> p_user_id
               FOR UPDATE) a;
        IF v_other_admins = 0 THEN
            RAISE EXCEPTION 'Cannot deactivate the last active admin' USING ERRCODE = 'NX409';
        END IF;
    END IF;

    UPDATE users SET is_active = p_is_active, updated_at = now()
     WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
END;
$$;
