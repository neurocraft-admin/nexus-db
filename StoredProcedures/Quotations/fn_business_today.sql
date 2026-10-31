-- Today's calendar date in the business time zone (app_settings business_time_zone, default UTC). A quotation is
-- valid "until" a date in that zone, so expiry and default dates must not use the database server's own clock zone.
CREATE OR REPLACE FUNCTION fn_business_today(p_tenant_id integer)
RETURNS date
LANGUAGE sql STABLE AS $$
    SELECT (now() AT TIME ZONE COALESCE(fn_get_setting(p_tenant_id, 'business_time_zone'), 'UTC'))::date;
$$;
