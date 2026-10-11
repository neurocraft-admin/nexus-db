CREATE OR REPLACE PROCEDURE sp_record_login_success(p_tenant_id integer, p_user_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE users
       SET failed_attempts = 0, locked_until = NULL, last_login_at = now(), updated_at = now()
     WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
END;
$$;
