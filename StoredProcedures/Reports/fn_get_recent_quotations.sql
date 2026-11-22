-- The newest quotations: number, who it is for, a short description (the first PACKAGE line, else the first line), total (tax-inclusive),
-- status. p_visible_to = a user's OWN quotations (made by them or on a lead assigned to them); NULL = everyone's. This is stricter than the
-- Quotations list, which also shows a staff user the quotations that have no lead.
CREATE OR REPLACE FUNCTION fn_get_recent_quotations(p_tenant_id integer, p_visible_to integer, p_limit integer)
RETURNS TABLE (quotation_id bigint, quotation_no varchar, party_name varchar, package_label varchar, total_amount numeric,
               status varchar, created_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT v.quotation_id, v.quotation_no, v.party_name, pl.package_label, v.total_amount, v.status, v.created_at
      FROM vw_quotation_summary v
      LEFT JOIN LATERAL (SELECT ql.description AS package_label FROM quotation_lines ql WHERE ql.quotation_id = v.quotation_id
                          ORDER BY (ql.line_type = 'package') DESC, ql.sort_order, ql.quotation_line_id LIMIT 1) pl ON true
     WHERE v.tenant_id = p_tenant_id AND (p_visible_to IS NULL OR v.created_by = p_visible_to OR v.lead_assigned_to = p_visible_to)
     ORDER BY v.created_at DESC, v.quotation_id DESC
     LIMIT p_limit;
$$;
