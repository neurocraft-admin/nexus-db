-- One staff member, in the shape of fn_get_staff (any staff-type user, active or not). No rows when the user does not exist, is in
-- another tenant, or is not a staff-type user (an admin account is not edited from the Staff screen).
CREATE OR REPLACE FUNCTION fn_get_staff_by_id(p_tenant_id integer, p_user_id integer)
RETURNS TABLE (user_id integer, user_name varchar, full_name varchar, mobile varchar, role_id integer, role_name varchar,
               is_active boolean, must_change_password boolean, last_login_at timestamptz, employee_code varchar,
               designation varchar, mobile_alt varchar, joining_date date, notes varchar, can_receive_work boolean,
               open_tasks bigint, open_tickets bigint, created_at timestamptz)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT s.user_id, s.user_name, s.full_name, s.mobile, s.role_id, s.role_name, s.is_active, s.must_change_password, s.last_login_at,
           s.employee_code, s.designation, s.mobile_alt, s.joining_date, s.notes, s.can_receive_work, s.open_tasks, s.open_tickets, s.created_at
      FROM fn_get_staff(p_tenant_id, NULL, true) s
     WHERE s.user_id = p_user_id;
END;
$$;
