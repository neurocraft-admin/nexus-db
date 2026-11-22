-- Active leads created in the range (business days, inclusive). p_visible_to is a staff user's id: only the leads assigned to them.
-- NULL counts everyone's.
CREATE OR REPLACE FUNCTION fn_count_leads_created(p_tenant_id integer, p_from date, p_to date, p_visible_to integer)
RETURNS bigint
LANGUAGE sql STABLE AS $$
    SELECT count(*)
      FROM vw_lead_pipeline v
     WHERE v.tenant_id = p_tenant_id AND v.created_date BETWEEN p_from AND p_to
       AND (p_visible_to IS NULL OR v.assigned_to = p_visible_to);
$$;
