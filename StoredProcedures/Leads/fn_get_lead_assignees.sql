-- The users a lead can be assigned to (active users), for the assignee picker. It exists so a person who may work
-- with leads does not also need permission to view the Users screen.
CREATE OR REPLACE FUNCTION fn_get_lead_assignees(p_tenant_id integer)
RETURNS TABLE (user_id integer, full_name varchar, user_type varchar)
LANGUAGE sql STABLE AS $$
    SELECT u.user_id, u.full_name, u.user_type
      FROM users u
     WHERE u.tenant_id = p_tenant_id AND u.is_active
     ORDER BY u.full_name, u.user_id;
$$;
