-- The date range of a dashboard period, in the business time zone, and the range it is compared with.
--   p_period: this_month, last_month, this_quarter, this_financial_year. Quarters and the financial year start from the
--   financial_year_start_month setting (default 4 = April).
--   A period that is still running is compared with the SAME NUMBER OF ELAPSED DAYS of the one before it (the first 15 days of
--   this month against the first 15 days of last month), so a part-month is never set against a whole month. A finished period
--   (last month) is compared with the whole period before it.
--   22023 invalid parameter - an unknown period (COLUMN period)
CREATE OR REPLACE FUNCTION fn_get_period_range(p_tenant_id integer, p_period varchar, p_as_of date DEFAULT NULL)
RETURNS TABLE (period_from date, period_to date, prev_from date, prev_to date, period_label varchar, prev_label varchar)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    c_default_fy_month CONSTANT integer := 4;
    c_months_in_quarter CONSTANT integer := 3;
    c_months_in_year CONSTANT integer := 12;
    v_today   date := COALESCE(p_as_of, fn_business_today(p_tenant_id));
    v_fy      integer := COALESCE(CASE WHEN fn_get_setting(p_tenant_id, 'financial_year_start_month') ~ '^([1-9]|1[0-2])$'
                                       THEN fn_get_setting(p_tenant_id, 'financial_year_start_month')::integer END, c_default_fy_month);
    v_since   integer := (extract(month FROM v_today)::integer - v_fy + c_months_in_year) % c_months_in_year;
    v_len     integer;
    v_from    date;
BEGIN
    IF p_period NOT IN ('this_month', 'last_month', 'this_quarter', 'this_financial_year') THEN
        RAISE EXCEPTION 'Choose this month, last month, this quarter or this financial year' USING ERRCODE = '22023', COLUMN = 'period';
    END IF;
    v_len := CASE p_period WHEN 'this_quarter' THEN c_months_in_quarter WHEN 'this_financial_year' THEN c_months_in_year ELSE 1 END;
    v_from := CASE p_period
                  WHEN 'this_month' THEN date_trunc('month', v_today)::date
                  WHEN 'last_month' THEN (date_trunc('month', v_today) - interval '1 month')::date
                  WHEN 'this_quarter' THEN (date_trunc('month', v_today) - make_interval(months => v_since % c_months_in_quarter))::date
                  ELSE (date_trunc('month', v_today) - make_interval(months => v_since))::date END;
    period_from := v_from;
    period_to := (v_from + make_interval(months => v_len))::date - 1;
    prev_from := (v_from - make_interval(months => v_len))::date;
    prev_to := CASE WHEN p_period = 'last_month' THEN v_from - 1 ELSE least(prev_from + (v_today - v_from), v_from - 1) END;
    period_label := CASE p_period WHEN 'this_month' THEN 'This month' WHEN 'last_month' THEN to_char(v_from, 'FMMonth YYYY')
                                  WHEN 'this_quarter' THEN 'This quarter' ELSE 'This financial year' END;
    prev_label := CASE WHEN v_len = 1 THEN to_char(prev_from, 'FMMonth') WHEN v_len = c_months_in_quarter THEN 'the previous quarter'
                       ELSE 'last financial year' END;
    RETURN NEXT;
END;
$$;
