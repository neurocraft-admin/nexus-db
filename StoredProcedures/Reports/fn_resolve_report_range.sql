-- The range a report runs over: the two days given, or the current month in the business time zone when BOTH are missing. One missing
-- day is refused. The range is then checked (fn_check_report_range).
--   22023 invalid parameter - one day only, an end before the start, more than 366 days (COLUMN from or to)
CREATE OR REPLACE FUNCTION fn_resolve_report_range(p_tenant_id integer, p_from date, p_to date)
RETURNS TABLE (range_from date, range_to date)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    IF p_from IS NULL AND p_to IS NULL THEN
        SELECT r.period_from, r.period_to INTO range_from, range_to FROM fn_get_period_range(p_tenant_id, 'this_month') r;
    ELSE
        range_from := p_from;
        range_to := p_to;
    END IF;
    PERFORM fn_check_report_range(range_from, range_to);
    RETURN NEXT;
END;
$$;
