-- The customers whose credit is past its terms, most overdue first, with how many there are in all (total_count on every row).
-- Reads fn_get_customer_dues. p_as_of is a moment (default now); the day is taken in the business time zone.
CREATE OR REPLACE FUNCTION fn_get_overdue_payments(p_tenant_id integer, p_limit integer, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (customer_id bigint, customer_name varchar, mobile varchar, balance numeric, days_overdue integer, total_count bigint)
LANGUAGE sql STABLE AS $$
    SELECT d.customer_id, d.customer_name, d.mobile, d.balance, d.days_overdue, count(*) OVER ()
      FROM fn_get_customer_dues(p_tenant_id, fn_business_date_of(p_tenant_id, COALESCE(p_as_of, now()))) d
     WHERE d.days_overdue > 0
     ORDER BY d.days_overdue DESC, d.balance DESC, d.customer_id
     LIMIT p_limit;
$$;
