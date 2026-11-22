-- The rows of the quotation conversion report, one per period (p_group_by 'month' or 'week'; weeks start on Monday), for the quotations CREATED in
-- the range. Used by fn_report_quotation_conversion, which adds the total row. The order columns count orders by the period they were CREATED and by
-- the period they were FULFILLED, so they can fall in a different period from the quotation they came from. A period with no quotations but with
-- orders is still listed.
CREATE OR REPLACE FUNCTION fn_get_conversion_buckets(p_tenant_id integer, p_from date, p_to date, p_group_by varchar)
RETURNS TABLE (bucket date, created bigint, sent bigint, approved bigint, rejected bigint, expired bigint, converted bigint, created_value numeric,
               approved_value numeric, orders_created bigint, orders_created_value numeric, orders_fulfilled bigint, orders_fulfilled_value numeric)
LANGUAGE sql STABLE AS $$
    WITH q AS (
        SELECT date_trunc(p_group_by, v.created_date)::date AS bucket, count(*) AS created, count(*) FILTER (WHERE v.was_sent) AS sent,
               count(*) FILTER (WHERE v.was_approved) AS approved, count(*) FILTER (WHERE v.status = 'rejected') AS rejected,
               count(*) FILTER (WHERE v.status = 'expired') AS expired, count(*) FILTER (WHERE v.status = 'converted') AS converted,
               sum(v.total_amount) AS created_value, COALESCE(sum(v.total_amount) FILTER (WHERE v.was_approved), 0) AS approved_value
          FROM vw_quotation_summary v WHERE v.tenant_id = p_tenant_id AND v.created_date BETWEEN p_from AND p_to GROUP BY 1
    ), oc AS (
        SELECT date_trunc(p_group_by, o.created_date)::date AS bucket, count(*) AS n, sum(o.total_amount) AS value
          FROM vw_order_report o WHERE o.tenant_id = p_tenant_id AND o.created_date BETWEEN p_from AND p_to GROUP BY 1
    ), ful AS (
        SELECT date_trunc(p_group_by, o.fulfilled_date)::date AS bucket, count(*) AS n, sum(o.total_amount) AS value
          FROM vw_order_report o
         WHERE o.tenant_id = p_tenant_id AND o.status = 'fulfilled' AND o.fulfilled_date BETWEEN p_from AND p_to GROUP BY 1
    )
    SELECT k.bucket, COALESCE(q.created, 0), COALESCE(q.sent, 0), COALESCE(q.approved, 0), COALESCE(q.rejected, 0), COALESCE(q.expired, 0),
           COALESCE(q.converted, 0), COALESCE(q.created_value, 0), COALESCE(q.approved_value, 0), COALESCE(oc.n, 0), COALESCE(oc.value, 0),
           COALESCE(ful.n, 0), COALESCE(ful.value, 0)
      FROM (SELECT q0.bucket FROM q q0 UNION SELECT oc0.bucket FROM oc oc0 UNION SELECT f0.bucket FROM ful f0) k
      LEFT JOIN q ON q.bucket = k.bucket LEFT JOIN oc ON oc.bucket = k.bucket LEFT JOIN ful ON ful.bucket = k.bucket;
$$;
