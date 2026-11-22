-- Report: quotation conversion by month or week (p_group_by 'month' or 'week', weeks start on Monday), over the quotations CREATED in the range
-- (business days, inclusive; both days missing = the current month, at most 366 days). One row per period plus a final TOTAL row (is_total).
--   created, sent (ever sent), approved (ever approved, including ones later converted), rejected / expired / converted (their status now)
--   conversion_rate = approved / sent as a percentage with one decimal, 0 when nothing was sent; the total row's rate comes from the totals.
--   Values are tax-inclusive. The order columns put total order value beside the conversion (see fn_get_conversion_buckets).
--   22023 invalid parameter - a bad group (COLUMN groupBy) or range (COLUMN from or to)
CREATE OR REPLACE FUNCTION fn_report_quotation_conversion(p_tenant_id integer, p_from date, p_to date, p_group_by varchar)
RETURNS TABLE (period_start date, created bigint, sent bigint, approved bigint, rejected bigint, expired bigint, converted bigint,
               conversion_rate numeric, created_value numeric, approved_value numeric, orders_created bigint, orders_created_value numeric,
               orders_fulfilled bigint, orders_fulfilled_value numeric, is_total boolean)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_from date;
    v_to   date;
BEGIN
    IF p_group_by IS NULL OR p_group_by NOT IN ('month', 'week') THEN
        RAISE EXCEPTION 'Group by month or week' USING ERRCODE = '22023', COLUMN = 'groupBy';
    END IF;
    SELECT r.range_from, r.range_to INTO v_from, v_to FROM fn_resolve_report_range(p_tenant_id, p_from, p_to) r;
    RETURN QUERY
    WITH b AS (SELECT x.bucket, x.created, x.sent, x.approved, x.rejected, x.expired, x.converted, x.created_value, x.approved_value, x.orders_created,
                      x.orders_created_value, x.orders_fulfilled, x.orders_fulfilled_value FROM fn_get_conversion_buckets(p_tenant_id, v_from, v_to, p_group_by) x)
    SELECT b.bucket, b.created, b.sent, b.approved, b.rejected, b.expired, b.converted, fn_conversion_pct(b.approved, b.sent), b.created_value,
           b.approved_value, b.orders_created, b.orders_created_value, b.orders_fulfilled, b.orders_fulfilled_value, false FROM b
    UNION ALL
    SELECT NULL::date, COALESCE(sum(b.created), 0)::bigint, COALESCE(sum(b.sent), 0)::bigint, COALESCE(sum(b.approved), 0)::bigint,
           COALESCE(sum(b.rejected), 0)::bigint, COALESCE(sum(b.expired), 0)::bigint, COALESCE(sum(b.converted), 0)::bigint,
           fn_conversion_pct(COALESCE(sum(b.approved), 0)::bigint, COALESCE(sum(b.sent), 0)::bigint), COALESCE(sum(b.created_value), 0),
           COALESCE(sum(b.approved_value), 0), COALESCE(sum(b.orders_created), 0)::bigint, COALESCE(sum(b.orders_created_value), 0),
           COALESCE(sum(b.orders_fulfilled), 0)::bigint, COALESCE(sum(b.orders_fulfilled_value), 0), true FROM b
    ORDER BY 15, 1;
END;
$$;
