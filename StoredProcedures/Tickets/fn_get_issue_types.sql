-- The issue types, in dropdown order. p_active_only true (the portal's dropdown, the staff ticket form) leaves out the
-- ones an admin has switched off; false (the Issue types screen) lists them all.
CREATE OR REPLACE FUNCTION fn_get_issue_types(p_tenant_id integer, p_active_only boolean)
RETURNS TABLE (issue_type_id integer, issue_type_name varchar, sort_order integer, is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT t.issue_type_id, t.issue_type_name, t.sort_order, t.is_active
      FROM issue_types t
     WHERE t.tenant_id = p_tenant_id
       AND (NOT COALESCE(p_active_only, false) OR t.is_active)
     ORDER BY t.sort_order, t.issue_type_name, t.issue_type_id;
$$;
