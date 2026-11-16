-- The Staff screen's list: every staff-type user (whatever their role: Staff, Sales, Clerk ...) with the optional profile, whether
-- their role can see My work (can_receive_work: whether they can be given tasks), and their open work.
--   p_search            the name, user name, employee code or designation anywhere, ignoring case (plain text)
--   p_include_inactive  false leaves out deactivated people
CREATE OR REPLACE FUNCTION fn_get_staff(p_tenant_id integer, p_search varchar, p_include_inactive boolean)
RETURNS TABLE (user_id integer, user_name varchar, full_name varchar, mobile varchar, role_id integer, role_name varchar,
               is_active boolean, must_change_password boolean, last_login_at timestamptz, employee_code varchar,
               designation varchar, mobile_alt varchar, joining_date date, notes varchar, can_receive_work boolean,
               open_tasks bigint, open_tickets bigint, created_at timestamptz)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT u.user_id, u.user_name, u.full_name, u.mobile, u.role_id, r.role_name, u.is_active, u.must_change_password, u.last_login_at,
           p.employee_code, p.designation, p.mobile_alt, p.joining_date, p.notes,
           fn_role_can_receive_work(p_tenant_id, u.role_id),
           (SELECT count(*) FROM tasks t WHERE t.tenant_id = p_tenant_id AND t.assigned_to = u.user_id AND t.status IN ('assigned', 'in_progress')),
           (SELECT count(*) FROM tickets k WHERE k.tenant_id = p_tenant_id AND k.assigned_to = u.user_id AND k.status IN ('open', 'in_progress')),
           u.created_at
      FROM users u
      JOIN roles r ON r.role_id = u.role_id
      LEFT JOIN staff_profiles p ON p.user_id = u.user_id
     WHERE u.tenant_id = p_tenant_id AND u.user_type = 'staff'
       AND (COALESCE(p_include_inactive, false) OR u.is_active)
       AND (p_search IS NULL OR btrim(p_search) = ''
            OR position(lower(btrim(p_search)) IN lower(u.full_name || ' ' || u.user_name || ' ' || COALESCE(p.employee_code, '') || ' ' || COALESCE(p.designation, ''))) > 0)
     ORDER BY u.full_name, u.user_id;
END;
$$;
