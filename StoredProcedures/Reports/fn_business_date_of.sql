-- The calendar date of a moment in the business time zone (app_settings business_time_zone, default UTC). The dashboard works in
-- business days, and tests pass an "as of" moment instead of reading the clock.
CREATE OR REPLACE FUNCTION fn_business_date_of(p_tenant_id integer, p_moment timestamptz)
RETURNS date
LANGUAGE sql STABLE AS $$
    SELECT (p_moment AT TIME ZONE COALESCE(fn_get_setting(p_tenant_id, 'business_time_zone'), 'UTC'))::date;
$$;
