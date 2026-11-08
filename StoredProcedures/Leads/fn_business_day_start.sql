-- The moment a calendar day begins in the business time zone (app_settings business_time_zone, default UTC), so a
-- date filter means the business's day and not the database server's. Used by the lead list and summary.
CREATE OR REPLACE FUNCTION fn_business_day_start(p_tenant_id integer, p_day date)
RETURNS timestamptz
LANGUAGE sql STABLE AS $$
    SELECT p_day::timestamp AT TIME ZONE COALESCE(fn_get_setting(p_tenant_id, 'business_time_zone'), 'UTC');
$$;
