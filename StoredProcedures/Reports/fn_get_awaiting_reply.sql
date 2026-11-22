-- Quotations waiting for the customer: status sent (an expired one is no longer waiting), with their tax-inclusive total.
-- p_visible_to limits to a user's OWN quotations (made by them, or on a lead assigned to them); NULL = everyone's.
CREATE OR REPLACE FUNCTION fn_get_awaiting_reply(p_tenant_id integer, p_visible_to integer)
RETURNS TABLE (quotation_count bigint, quotation_value numeric)
LANGUAGE sql STABLE AS $$
    SELECT count(*), COALESCE(sum(v.total_amount), 0)
      FROM vw_quotation_summary v
     WHERE v.tenant_id = p_tenant_id AND v.status = 'sent'
       AND (p_visible_to IS NULL OR v.created_by = p_visible_to OR v.lead_assigned_to = p_visible_to);
$$;
