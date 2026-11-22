-- The pipeline by status, every active status listed (0 when empty), in pipeline order. An OPEN status counts the leads that are in it now;
-- Won and Lost count the leads CLOSED in the range (p_from/p_to, business days). p_visible_to = a staff user's own leads (NULL = everyone's).
CREATE OR REPLACE FUNCTION fn_get_lead_pipeline(p_tenant_id integer, p_from date, p_to date, p_visible_to integer DEFAULT NULL)
RETURNS TABLE (lead_status_id integer, status_name varchar, sort_order integer, is_won boolean, is_lost boolean, lead_count bigint)
LANGUAGE sql STABLE AS $$
    SELECT st.lead_status_id, st.status_name, st.sort_order, st.is_won, st.is_lost,
           (SELECT count(*) FROM vw_lead_pipeline v
             WHERE v.tenant_id = p_tenant_id AND v.lead_status_id = st.lead_status_id
               AND (p_visible_to IS NULL OR v.assigned_to = p_visible_to)
               AND CASE WHEN st.is_won OR st.is_lost THEN v.closed_date BETWEEN p_from AND p_to ELSE NOT v.is_closed END)
      FROM lead_statuses st
     WHERE st.tenant_id = p_tenant_id AND st.is_active
     ORDER BY st.sort_order, st.lead_status_id;
$$;
