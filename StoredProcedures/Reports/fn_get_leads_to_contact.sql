-- "Contact these leads first": open leads still in the FIRST open stage (the New stage), oldest first. age_days = whole days since the lead was
-- added. p_visible_to = a staff user's own leads (NULL = everyone's). Source and age only: a lead has no "interest" field.
CREATE OR REPLACE FUNCTION fn_get_leads_to_contact(p_tenant_id integer, p_visible_to integer, p_limit integer, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (lead_id bigint, lead_no varchar, lead_name varchar, mobile varchar, source_name varchar, created_at timestamptz, age_days integer)
LANGUAGE sql STABLE AS $$
    SELECT v.lead_id, v.lead_no, v.lead_name, v.mobile, v.source_name, v.created_at,
           floor(extract(epoch FROM (COALESCE(p_as_of, now()) - v.created_at)) / 86400)::integer
      FROM vw_lead_pipeline v
     WHERE v.tenant_id = p_tenant_id AND NOT v.is_closed AND (p_visible_to IS NULL OR v.assigned_to = p_visible_to)
       AND v.lead_status_id = (SELECT st.lead_status_id FROM lead_statuses st
                                WHERE st.tenant_id = p_tenant_id AND st.is_active AND NOT st.is_won AND NOT st.is_lost
                                ORDER BY st.sort_order, st.lead_status_id LIMIT 1)
     ORDER BY v.created_at, v.lead_id
     LIMIT p_limit;
$$;
