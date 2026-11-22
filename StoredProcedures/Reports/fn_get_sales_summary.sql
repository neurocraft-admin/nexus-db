-- The Sales view's headline numbers for ONE user's own leads and quotations (p_visible_to = their id; NULL = the whole company, the same shape).
-- "Own" lead = assigned to them; "own" quotation = made by them or on a lead assigned to them.
--   not_contacted = open leads still in the FIRST open stage. won / won_value = leads closed as Won in the period and the tax-inclusive total
--   of own quotations approved in the period. conversion = won / new leads (0 when none), compared with the previous range (p_prev_*).
CREATE OR REPLACE FUNCTION fn_get_sales_summary(
    p_tenant_id integer, p_visible_to integer, p_from date, p_to date, p_prev_from date, p_prev_to date)
RETURNS TABLE (new_leads bigint, new_leads_prev bigint, open_leads bigint, not_contacted bigint, awaiting_reply_count bigint,
               awaiting_reply_value numeric, won bigint, won_value numeric, conversion numeric, conversion_prev numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_won_prev bigint := fn_count_leads_closed(p_tenant_id, p_prev_from, p_prev_to, p_visible_to, true);
BEGIN
    new_leads := fn_count_leads_created(p_tenant_id, p_from, p_to, p_visible_to);
    new_leads_prev := fn_count_leads_created(p_tenant_id, p_prev_from, p_prev_to, p_visible_to);
    won := fn_count_leads_closed(p_tenant_id, p_from, p_to, p_visible_to, true);
    conversion := fn_conversion_pct(won, new_leads);
    conversion_prev := fn_conversion_pct(v_won_prev, new_leads_prev);
    SELECT COALESCE(s.open_total, 0), COALESCE(s.first_count, 0) INTO open_leads, not_contacted
      FROM fn_get_open_lead_stages(p_tenant_id, p_visible_to) s;
    open_leads := COALESCE(open_leads, 0);
    not_contacted := COALESCE(not_contacted, 0);
    SELECT a.quotation_count, a.quotation_value INTO awaiting_reply_count, awaiting_reply_value FROM fn_get_awaiting_reply(p_tenant_id, p_visible_to) a;
    SELECT COALESCE(sum(v.total_amount), 0) INTO won_value
      FROM vw_quotation_summary v
     WHERE v.tenant_id = p_tenant_id AND v.was_approved AND fn_business_date_of(p_tenant_id, v.approved_at) BETWEEN p_from AND p_to
       AND (p_visible_to IS NULL OR v.created_by = p_visible_to OR v.lead_assigned_to = p_visible_to);
    RETURN NEXT;
END;
$$;
