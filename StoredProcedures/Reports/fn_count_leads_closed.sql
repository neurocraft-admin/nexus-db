-- Leads closed in the range as Won (p_won true) or Lost (false), by the business day they were closed. p_visible_to limits to a staff
-- user's own leads (NULL = everyone's).
CREATE OR REPLACE FUNCTION fn_count_leads_closed(p_tenant_id integer, p_from date, p_to date, p_visible_to integer, p_won boolean)
RETURNS bigint
LANGUAGE sql STABLE AS $$
    SELECT count(*)
      FROM vw_lead_pipeline v
     WHERE v.tenant_id = p_tenant_id AND v.is_closed AND v.closed_date BETWEEN p_from AND p_to
       AND ((p_won AND v.is_won) OR (NOT p_won AND v.is_lost))
       AND (p_visible_to IS NULL OR v.assigned_to = p_visible_to);
$$;
