-- Switches a staff-type user on or off (deactivating blocks sign-in). Delegates to fn_set_user_active, so the same rules hold
-- whichever screen asks: a person with open tasks or open tickets cannot be deactivated until their work is reassigned.
--   P0002 not found     - unknown user, or not a staff-type user (admin accounts are not handled here)
--   NX409 rule conflict - open work (see sp_assert_no_open_work)
CREATE OR REPLACE FUNCTION fn_set_staff_active(p_tenant_id integer, p_user_id integer, p_is_active boolean)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM 1 FROM users u WHERE u.user_id = p_user_id AND u.tenant_id = p_tenant_id AND u.user_type = 'staff';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Staff member % not found', p_user_id USING ERRCODE = 'P0002';
    END IF;
    PERFORM fn_set_user_active(p_tenant_id, p_user_id, p_is_active);
END;
$$;
