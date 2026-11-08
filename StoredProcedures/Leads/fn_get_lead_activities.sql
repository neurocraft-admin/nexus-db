-- One lead's history, newest first. The visibility rule is part of the query, not left to the caller: for a lead the
-- user may not see (a staff user and a lead assigned to someone else) it returns nothing, exactly as for a lead that
-- does not exist, so the API cannot leak another person's notes by asking for the history directly.
CREATE OR REPLACE FUNCTION fn_get_lead_activities(p_tenant_id integer, p_lead_id bigint, p_visible_to integer)
RETURNS TABLE (activity_id bigint, activity_type varchar, old_value varchar, new_value varchar, note varchar,
               created_by integer, created_by_name varchar, created_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT a.activity_id, a.activity_type, a.old_value, a.new_value, a.note, a.created_by, u.full_name, a.created_at
      FROM lead_activities a
      JOIN leads l ON l.lead_id = a.lead_id AND l.tenant_id = a.tenant_id
      LEFT JOIN users u ON u.user_id = a.created_by
     WHERE a.tenant_id = p_tenant_id AND a.lead_id = p_lead_id
       AND (p_visible_to IS NULL OR l.assigned_to = p_visible_to)
     ORDER BY a.created_at DESC, a.activity_id DESC;
$$;
