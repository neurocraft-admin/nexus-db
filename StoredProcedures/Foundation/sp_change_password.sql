-- Self-service change after the API has verified the current password.
CREATE OR REPLACE PROCEDURE sp_change_password(
    p_tenant_id integer, p_user_id integer, p_password_hash varchar)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE users
       SET password_hash = p_password_hash, must_change_password = false, updated_at = now()
     WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found', p_user_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;
