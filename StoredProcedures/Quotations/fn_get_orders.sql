-- The order list, newest first, with filters and paging. Each row carries total_count (rows matching the filter
-- before paging). p_status, p_customer_id, p_from, p_to (order dates in the business time zone, inclusive) and
-- p_search (order number, quotation number or customer name, plain text, ignoring case) are all optional.
-- p_limit NULL returns everything (the API caps what it asks for).
CREATE OR REPLACE FUNCTION fn_get_orders(
    p_tenant_id integer, p_status varchar, p_customer_id bigint, p_from date, p_to date, p_search varchar,
    p_limit integer, p_offset integer)
RETURNS TABLE (order_id bigint, order_no varchar, quotation_id bigint, quotation_no varchar, customer_id bigint,
               customer_name varchar, status varchar, payment_mode varchar, total_amount numeric,
               fulfilled_at timestamptz, created_at timestamptz, total_count bigint)
LANGUAGE sql STABLE AS $$
    WITH tz AS (
        SELECT COALESCE(fn_get_setting(p_tenant_id, 'business_time_zone'), 'UTC') AS name
    )
    SELECT o.order_id, o.order_no, o.quotation_id, q.quotation_no, o.customer_id, c.customer_name, o.status,
           o.payment_mode, o.total_amount, o.fulfilled_at, o.created_at, count(*) OVER ()
      FROM orders o
      JOIN quotations q ON q.quotation_id = o.quotation_id
      JOIN customers c ON c.customer_id = o.customer_id
      CROSS JOIN tz
     WHERE o.tenant_id = p_tenant_id
       AND (p_status IS NULL OR o.status = p_status)
       AND (p_customer_id IS NULL OR o.customer_id = p_customer_id)
       AND (p_from IS NULL OR o.created_at >= (p_from::timestamp AT TIME ZONE tz.name))
       AND (p_to IS NULL OR o.created_at < ((p_to + 1)::timestamp AT TIME ZONE tz.name))
       AND (p_search IS NULL OR btrim(p_search) = ''
            OR position(lower(btrim(p_search)) IN lower(o.order_no || ' ' || q.quotation_no || ' ' || c.customer_name)) > 0)
     ORDER BY o.created_at DESC, o.order_id DESC
     LIMIT p_limit OFFSET COALESCE(p_offset, 0);
$$;
