CREATE OR REPLACE PROCEDURE sp_record_login_failure(p_tenant_id integer, p_user_id integer)
LANGUAGE plpgsql AS $$
DECLARE
    -- Defaults apply only if the settings rows are missing.
    c_default_max_attempts  CONSTANT integer := 5;
    c_default_lock_minutes  CONSTANT integer := 15;
    v_max_attempts  integer;
    v_lock_minutes  integer;
    v_attempts      integer;
BEGIN
    v_max_attempts := COALESCE(fn_get_setting(p_tenant_id, 'login_max_attempts')::integer, c_default_max_attempts);
    v_lock_minutes := COALESCE(fn_get_setting(p_tenant_id, 'login_lock_minutes')::integer, c_default_lock_minutes);

    -- Single UPDATE so concurrent failures each count.
    UPDATE users
       SET failed_attempts = failed_attempts + 1, updated_at = now()
     WHERE user_id = p_user_id AND tenant_id = p_tenant_id
    RETURNING failed_attempts INTO v_attempts;

    IF v_attempts >= v_max_attempts THEN
        -- Counter restarts after a lock so one typo after the lock expires does not re-lock.
        UPDATE users
           SET locked_until = now() + make_interval(mins => v_lock_minutes),
               failed_attempts = 0, updated_at = now()
         WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
    END IF;
END;
$$;
