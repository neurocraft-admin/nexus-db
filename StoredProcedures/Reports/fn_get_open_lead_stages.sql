-- The open pipeline in one row: every open lead (active, not Won or Lost), and the first and last OPEN stage (by sort order) with their
-- counts, so a card can say "14 new, 6 in negotiation" whatever the owner has named the stages. p_visible_to = a staff user's own leads.
CREATE OR REPLACE FUNCTION fn_get_open_lead_stages(p_tenant_id integer, p_visible_to integer)
RETURNS TABLE (open_total bigint, first_name varchar, first_count bigint, last_name varchar, last_count bigint)
LANGUAGE sql STABLE AS $$
    WITH stages AS (
        SELECT st.lead_status_id, st.status_name, st.sort_order FROM lead_statuses st
         WHERE st.tenant_id = p_tenant_id AND st.is_active AND NOT st.is_won AND NOT st.is_lost
    ), counts AS (
        SELECT v.lead_status_id, count(*) AS lead_count FROM vw_lead_pipeline v
         WHERE v.tenant_id = p_tenant_id AND NOT v.is_closed AND (p_visible_to IS NULL OR v.assigned_to = p_visible_to)
         GROUP BY v.lead_status_id
    )
    SELECT (SELECT COALESCE(sum(c.lead_count), 0) FROM counts c)::bigint,
           f.status_name, COALESCE((SELECT c.lead_count FROM counts c WHERE c.lead_status_id = f.lead_status_id), 0),
           l.status_name, COALESCE((SELECT c.lead_count FROM counts c WHERE c.lead_status_id = l.lead_status_id), 0)
      FROM (SELECT s.lead_status_id, s.status_name FROM stages s ORDER BY s.sort_order, s.lead_status_id LIMIT 1) f,
           (SELECT s.lead_status_id, s.status_name FROM stages s ORDER BY s.sort_order DESC, s.lead_status_id DESC LIMIT 1) l;
$$;
