-- Revenue: the tax-inclusive total of the orders FULFILLED in the range (by the business day they were fulfilled). A credit order counts when
-- it is fulfilled, whether or not the customer has paid yet; what is still owed is the dues figure.
CREATE OR REPLACE FUNCTION fn_revenue_between(p_tenant_id integer, p_from date, p_to date)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(sum(o.total_amount), 0)
      FROM vw_order_report o
     WHERE o.tenant_id = p_tenant_id AND o.status = 'fulfilled' AND o.fulfilled_date BETWEEN p_from AND p_to;
$$;
