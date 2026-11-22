-- The front desk's numbers for ONE user: tickets they raised today (and how many are still unassigned), raised this week (Monday to today,
-- business time) and how many of those have been resolved, and their open tickets (raised by them OR assigned to them) with how many are
-- over ticket_overdue_days old.
CREATE OR REPLACE FUNCTION fn_get_my_ticket_summary(p_tenant_id integer, p_user_id integer, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (raised_today bigint, raised_today_unassigned bigint, raised_week bigint, raised_week_resolved bigint, open_mine bigint,
               open_mine_overdue bigint)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_now  timestamptz := COALESCE(p_as_of, now());
    v_day  date := fn_business_date_of(p_tenant_id, COALESCE(p_as_of, now()));
    v_week date := date_trunc('week', v_day)::date;
BEGIN
    SELECT count(*) FILTER (WHERE v.created_by = p_user_id AND v.created_date = v_day),
           count(*) FILTER (WHERE v.created_by = p_user_id AND v.created_date = v_day AND v.is_unassigned),
           count(*) FILTER (WHERE v.created_by = p_user_id AND v.created_date BETWEEN v_week AND v_day),
           count(*) FILTER (WHERE v.created_by = p_user_id AND v.created_date BETWEEN v_week AND v_day AND v.resolved_at IS NOT NULL),
           count(*) FILTER (WHERE v.is_open AND (v.created_by = p_user_id OR v.assigned_to = p_user_id)),
           count(*) FILTER (WHERE v.is_open AND (v.created_by = p_user_id OR v.assigned_to = p_user_id)
                            AND v.created_at < v_now - make_interval(days => fn_ticket_overdue_days(p_tenant_id)))
      INTO raised_today, raised_today_unassigned, raised_week, raised_week_resolved, open_mine, open_mine_overdue
      FROM vw_ticket_summary v WHERE v.tenant_id = p_tenant_id;
    RETURN NEXT;
END;
$$;
