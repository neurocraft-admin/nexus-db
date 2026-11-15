-- The people a ticket can be given to: every active user, staff and admin. It exists so a person who works with tickets
-- does not also need permission to view the Users screen (the API serves it as GET /api/tickets/technicians).
CREATE OR REPLACE FUNCTION fn_get_ticket_assignees(p_tenant_id integer)
RETURNS TABLE (user_id integer, full_name varchar, user_type varchar)
LANGUAGE sql STABLE AS $$
    SELECT u.user_id, u.full_name, u.user_type
      FROM users u
     WHERE u.tenant_id = p_tenant_id AND u.is_active
     ORDER BY u.full_name, u.user_id;
$$;
