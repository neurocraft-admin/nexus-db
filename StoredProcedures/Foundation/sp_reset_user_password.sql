-- Admin reset: forces the user to choose a new password at next login and clears any lockout.
CREATE OR REPLACE PROCEDURE sp_reset_user_password(
    p_tenant_id integer, p_user_id integer, p_password_hash varchar)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE users
       SET password_hash = p_password_hash, must_change_password = true,
           failed_attempts = 0, locked_until = NULL, updated_at = now()
     WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found', p_user_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;
