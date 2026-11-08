-- The pipeline statuses in order, with the Won and Lost flags the code goes by (never the names). p_active_only
-- true leaves out retired statuses.
CREATE OR REPLACE FUNCTION fn_get_lead_statuses(p_tenant_id integer, p_active_only boolean)
RETURNS TABLE (lead_status_id integer, status_name varchar, sort_order integer, is_won boolean, is_lost boolean,
               is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT s.lead_status_id, s.status_name, s.sort_order, s.is_won, s.is_lost, s.is_active
      FROM lead_statuses s
     WHERE s.tenant_id = p_tenant_id
       AND (NOT COALESCE(p_active_only, false) OR s.is_active)
     ORDER BY s.sort_order, s.lead_status_id;
$$;
