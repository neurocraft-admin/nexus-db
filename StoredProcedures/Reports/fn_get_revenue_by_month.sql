-- Revenue for each of the last p_months calendar months (default 6, the month of p_as_of last), tax-inclusive, oldest first. A month with
-- no fulfilled order is listed with 0. Revenue is the total of orders FULFILLED in the month (see fn_revenue_between).
CREATE OR REPLACE FUNCTION fn_get_revenue_by_month(p_tenant_id integer, p_months integer DEFAULT 6, p_as_of date DEFAULT NULL)
RETURNS TABLE (month_start date, revenue numeric, orders_fulfilled bigint)
LANGUAGE sql STABLE AS $$
    WITH m AS (
        SELECT (date_trunc('month', COALESCE(p_as_of, fn_business_today(p_tenant_id))) - make_interval(months => g))::date AS month_start
          FROM generate_series(p_months - 1, 0, -1) g
    )
    SELECT m.month_start, COALESCE(sum(o.total_amount), 0), count(o.order_id)
      FROM m
      LEFT JOIN vw_order_report o ON o.tenant_id = p_tenant_id AND o.status = 'fulfilled'
           AND o.fulfilled_date >= m.month_start AND o.fulfilled_date < (m.month_start + interval '1 month')::date
     GROUP BY m.month_start
     ORDER BY m.month_start;
$$;
