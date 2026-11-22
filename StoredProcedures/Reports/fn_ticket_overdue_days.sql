-- How old an open ticket may get before it counts as overdue: the ticket_overdue_days setting, 7 when it is missing or not a number.
CREATE OR REPLACE FUNCTION fn_ticket_overdue_days(p_tenant_id integer)
RETURNS integer
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(CASE WHEN fn_get_setting(p_tenant_id, 'ticket_overdue_days') ~ '^[0-9]{1,3}$'
                         THEN fn_get_setting(p_tenant_id, 'ticket_overdue_days')::integer END, 7);
$$;
