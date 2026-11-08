-- The lead sources for dropdowns and the source screen, in their sort order. p_active_only true leaves out
-- deactivated sources (what a lead form offers); false returns all.
CREATE OR REPLACE FUNCTION fn_get_lead_sources(p_tenant_id integer, p_active_only boolean)
RETURNS TABLE (lead_source_id integer, source_name varchar, source_code varchar, sort_order integer, is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT s.lead_source_id, s.source_name, s.source_code, s.sort_order, s.is_active
      FROM lead_sources s
     WHERE s.tenant_id = p_tenant_id
       AND (NOT COALESCE(p_active_only, false) OR s.is_active)
     ORDER BY s.sort_order, s.source_name, s.lead_source_id;
$$;
