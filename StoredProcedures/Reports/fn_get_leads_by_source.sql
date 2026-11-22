-- Leads created in the range (business days, inclusive) by source, biggest first; a source with none is left out. p_visible_to = a staff
-- user's own leads (NULL = everyone's).
CREATE OR REPLACE FUNCTION fn_get_leads_by_source(p_tenant_id integer, p_from date, p_to date, p_visible_to integer DEFAULT NULL)
RETURNS TABLE (lead_source_id integer, source_name varchar, lead_count bigint)
LANGUAGE sql STABLE AS $$
    SELECT v.lead_source_id, v.source_name, count(*)
      FROM vw_lead_pipeline v
     WHERE v.tenant_id = p_tenant_id AND v.created_date BETWEEN p_from AND p_to
       AND (p_visible_to IS NULL OR v.assigned_to = p_visible_to)
     GROUP BY v.lead_source_id, v.source_name
     ORDER BY count(*) DESC, v.source_name;
$$;
