-- The admin dashboard's headline numbers in ONE call, company-wide. p_from/p_to is the period (inclusive business days) and
-- p_prev_from/p_prev_to the range it is compared with (see fn_get_period_range); p_as_of is the moment "now" for ticket age and dues
-- (default now). Rates are percentages with one decimal; money is tax-inclusive.
--   Snapshot figures (open leads, dues, open and overdue tickets, quotes awaiting reply, low stock) are as of p_as_of, not the period.
--   lead_conversion = leads closed as Won in the period / leads created in the period (0 when none were created).
CREATE OR REPLACE FUNCTION fn_get_dashboard_summary(
    p_tenant_id integer, p_from date, p_to date, p_prev_from date, p_prev_to date, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (new_leads bigint, new_leads_prev bigint, leads_won bigint, leads_won_prev bigint, lead_conversion numeric,
               lead_conversion_prev numeric, revenue numeric, revenue_prev numeric, open_leads bigint, open_leads_first bigint,
               open_leads_first_name varchar, open_leads_last bigint, open_leads_last_name varchar, dues_total numeric,
               dues_overdue_customers bigint, open_tickets bigint, overdue_tickets bigint, awaiting_reply_count bigint,
               awaiting_reply_value numeric, low_stock_count bigint, low_stock_below_half bigint)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_now   timestamptz := COALESCE(p_as_of, now());
    v_day   date := fn_business_date_of(p_tenant_id, COALESCE(p_as_of, now()));
    v_stage record;
BEGIN
    new_leads := fn_count_leads_created(p_tenant_id, p_from, p_to, NULL);
    new_leads_prev := fn_count_leads_created(p_tenant_id, p_prev_from, p_prev_to, NULL);
    leads_won := fn_count_leads_closed(p_tenant_id, p_from, p_to, NULL, true);
    leads_won_prev := fn_count_leads_closed(p_tenant_id, p_prev_from, p_prev_to, NULL, true);
    lead_conversion := fn_conversion_pct(leads_won, new_leads);
    lead_conversion_prev := fn_conversion_pct(leads_won_prev, new_leads_prev);
    revenue := fn_revenue_between(p_tenant_id, p_from, p_to);
    revenue_prev := fn_revenue_between(p_tenant_id, p_prev_from, p_prev_to);
    SELECT s.open_total, s.first_count, s.first_name, s.last_count, s.last_name
      INTO open_leads, open_leads_first, open_leads_first_name, open_leads_last, open_leads_last_name
      FROM fn_get_open_lead_stages(p_tenant_id, NULL) s;
    SELECT COALESCE(sum(d.balance), 0), count(*) FILTER (WHERE d.days_overdue > 0) INTO dues_total, dues_overdue_customers
      FROM fn_get_customer_dues(p_tenant_id, v_day) d;
    SELECT count(*) FILTER (WHERE v.is_open),
           count(*) FILTER (WHERE v.is_open AND v.created_at < v_now - make_interval(days => fn_ticket_overdue_days(p_tenant_id)))
      INTO open_tickets, overdue_tickets FROM vw_ticket_summary v WHERE v.tenant_id = p_tenant_id;
    SELECT a.quotation_count, a.quotation_value INTO awaiting_reply_count, awaiting_reply_value FROM fn_get_awaiting_reply(p_tenant_id, NULL) a;
    SELECT count(*) FILTER (WHERE i.is_low), count(*) FILTER (WHERE i.is_below_half) INTO low_stock_count, low_stock_below_half
      FROM vw_inventory_status i WHERE i.tenant_id = p_tenant_id;
    open_leads := COALESCE(open_leads, 0);
    open_leads_first := COALESCE(open_leads_first, 0);
    open_leads_last := COALESCE(open_leads_last, 0);
    RETURN NEXT;
END;
$$;
