-- How many leads each source brought, and where they stand: one row per source and status that has at least one
-- lead (the Dashboard fills the gaps with zeros). Deactivated leads are not counted. p_from / p_to are the day the
-- lead was created, in the business time zone, inclusive (NULL = no limit). A staff user (p_visible_to) is counted
-- on their own leads only.
CREATE OR REPLACE FUNCTION fn_get_lead_source_summary(p_tenant_id integer, p_from date, p_to date, p_visible_to integer)
RETURNS TABLE (lead_source_id integer, source_name varchar, lead_status_id integer, status_name varchar, is_won boolean,
               is_lost boolean, lead_count bigint)
LANGUAGE sql STABLE AS $$
    SELECT s.lead_source_id, s.source_name, st.lead_status_id, st.status_name, st.is_won, st.is_lost, count(*)
      FROM leads l
      JOIN lead_sources s ON s.lead_source_id = l.lead_source_id
      JOIN lead_statuses st ON st.lead_status_id = l.lead_status_id
     WHERE l.tenant_id = p_tenant_id AND l.is_active
       AND (p_visible_to IS NULL OR l.assigned_to = p_visible_to)
       AND (p_from IS NULL OR l.created_at >= fn_business_day_start(p_tenant_id, p_from))
       AND (p_to IS NULL OR l.created_at < fn_business_day_start(p_tenant_id, p_to + 1))
     GROUP BY s.lead_source_id, s.source_name, s.sort_order, st.lead_status_id, st.status_name, st.sort_order, st.is_won, st.is_lost
     ORDER BY s.sort_order, s.source_name, st.sort_order;
$$;
