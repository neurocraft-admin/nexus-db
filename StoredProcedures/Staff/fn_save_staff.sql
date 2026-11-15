-- Creates (p_user_id NULL) or updates a staff-type user AND their profile in ONE transaction: if the profile cannot be saved (for
-- example a duplicate employee code) the user is not created either. A new user starts with must_change_password = true; the
-- password hash (made by the API from a generated temporary password) is used only when creating. A password changes through
-- sp_reset_user_password or sp_change_password. The user type is always 'staff'. Blank profile fields are stored as NULL.
--   22023 invalid parameter - a profile field that is too long or malformed (COLUMN names it)
--   P0002 not found         - unknown or inactive role (COLUMN roleId); on update, unknown user or not a staff-type user
--   NX409 rule conflict     - a role that cannot see My work, for someone who still has open tasks (COLUMN roleId)
--   23505 unique_violation  - the user name (uq_users_tenant_user_name) or the employee code (uq_staff_profiles_tenant_code) is taken
CREATE OR REPLACE FUNCTION fn_save_staff(
    p_tenant_id integer, p_user_id integer, p_user_name varchar, p_full_name varchar, p_mobile varchar, p_role_id integer,
    p_password_hash varchar, p_employee_code varchar, p_designation varchar, p_mobile_alt varchar, p_joining_date date, p_notes varchar)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    v_user_id integer;
BEGIN
    CALL sp_check_staff_profile(p_tenant_id, p_role_id, p_employee_code, p_designation, p_mobile_alt, p_notes);
    IF p_user_id IS NULL THEN
        INSERT INTO users (tenant_id, user_name, full_name, mobile, password_hash, role_id, user_type)
        VALUES (p_tenant_id, p_user_name, p_full_name, p_mobile, p_password_hash, p_role_id, 'staff')
        RETURNING users.user_id INTO v_user_id;
    ELSE
        CALL sp_check_staff_role_change(p_tenant_id, p_user_id, p_role_id);
        UPDATE users
           SET user_name = p_user_name, full_name = p_full_name, mobile = p_mobile, role_id = p_role_id, updated_at = now()
         WHERE users.user_id = p_user_id AND users.tenant_id = p_tenant_id AND users.user_type = 'staff'
        RETURNING users.user_id INTO v_user_id;
        IF v_user_id IS NULL THEN
            RAISE EXCEPTION 'Staff member % not found', p_user_id USING ERRCODE = 'P0002';
        END IF;
    END IF;
    INSERT INTO staff_profiles (user_id, tenant_id, employee_code, designation, mobile_alt, joining_date, notes)
    VALUES (v_user_id, p_tenant_id, NULLIF(btrim(p_employee_code), ''), NULLIF(btrim(p_designation), ''),
            NULLIF(btrim(p_mobile_alt), ''), p_joining_date, NULLIF(btrim(p_notes), ''))
    ON CONFLICT (user_id) DO UPDATE
       SET employee_code = EXCLUDED.employee_code, designation = EXCLUDED.designation, mobile_alt = EXCLUDED.mobile_alt,
           joining_date = EXCLUDED.joining_date, notes = EXCLUDED.notes, updated_at = now();
    RETURN v_user_id;
END;
$$;
