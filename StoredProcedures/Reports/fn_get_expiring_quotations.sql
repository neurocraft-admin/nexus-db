-- Sent quotations that stop being valid within the next 7 days (today included), soonest first. party_mobile is the customer's or the lead's, for
-- a Call button. p_visible_to = a user's OWN quotations (made by them or on a lead assigned to them); NULL = everyone's.
CREATE OR REPLACE FUNCTION fn_get_expiring_quotations(p_tenant_id integer, p_visible_to integer, p_limit integer, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (quotation_id bigint, quotation_no varchar, party_name varchar, party_mobile varchar, valid_until date, total_amount numeric,
               days_left integer)
LANGUAGE sql STABLE AS $$
    WITH today AS (SELECT fn_business_date_of(p_tenant_id, COALESCE(p_as_of, now())) AS day, 7 AS window_days)
    SELECT v.quotation_id, v.quotation_no, v.party_name, v.party_mobile, v.valid_until, v.total_amount, v.valid_until - t.day
      FROM vw_quotation_summary v CROSS JOIN today t
     WHERE v.tenant_id = p_tenant_id AND v.status = 'sent' AND v.valid_until BETWEEN t.day AND t.day + t.window_days
       AND (p_visible_to IS NULL OR v.created_by = p_visible_to OR v.lead_assigned_to = p_visible_to)
     ORDER BY v.valid_until, v.quotation_id
     LIMIT p_limit;
$$;
