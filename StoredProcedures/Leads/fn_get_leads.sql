-- The lead list with filters and paging. Each row carries total_count (rows matching the filter before paging).
-- Every filter is optional (NULL = no filter):
--   p_status_id, p_source_id, p_assigned_to
--   p_follow_up   'today' (due today), 'overdue' (before today) or 'due' (today or earlier); open leads only
--   p_search      the name, mobile or lead number anywhere, ignoring case (plain text, no wildcards)
--   p_from, p_to  the day the lead was created, in the business time zone, inclusive
--   p_closed_since  only leads closed (Won or Lost) on or after this day; leaves open leads out. The board asks for the
--                   last 30 days of Won and Lost this way
--   p_open_only   true leaves out Won and Lost leads
--   p_include_inactive  false (the default) leaves out deactivated leads
-- p_visible_to is the staff user's id: a staff user sees only the leads assigned to them, enforced here and not
-- only in the screen; NULL (an admin) sees all. is_overdue says an open lead's follow-up date has passed.
--   22023 invalid parameter - an unknown p_follow_up
CREATE OR REPLACE FUNCTION fn_get_leads(
    p_tenant_id integer, p_status_id integer, p_source_id integer, p_assigned_to integer, p_follow_up varchar,
    p_search varchar, p_from date, p_to date, p_closed_since date, p_open_only boolean, p_include_inactive boolean,
    p_visible_to integer, p_limit integer, p_offset integer)
RETURNS TABLE (lead_id bigint, lead_no varchar, lead_name varchar, mobile varchar, email varchar, lead_source_id integer, source_name varchar,
               lead_status_id integer, status_name varchar, is_won boolean, is_lost boolean, assigned_to integer, assigned_to_name varchar,
               expected_value numeric, next_follow_up_date date, is_overdue boolean, converted_customer_id bigint, is_active boolean,
               is_closed boolean, created_at timestamptz, total_count bigint)
LANGUAGE plpgsql AS $$
BEGIN
    CALL sp_check_lead_follow_up_filter(p_follow_up);
    RETURN QUERY
    SELECT l.lead_id, l.lead_no, l.lead_name, l.mobile, l.email, l.lead_source_id, s.source_name, l.lead_status_id, st.status_name,
           st.is_won, st.is_lost, l.assigned_to, u.full_name, l.expected_value, l.next_follow_up_date,
           COALESCE(NOT l.is_closed AND l.is_active AND l.next_follow_up_date < fn_business_today(p_tenant_id), false), l.converted_customer_id,
           l.is_active, l.is_closed, l.created_at, count(*) OVER ()
      FROM leads l
      JOIN lead_sources s ON s.lead_source_id = l.lead_source_id
      JOIN lead_statuses st ON st.lead_status_id = l.lead_status_id
      LEFT JOIN users u ON u.user_id = l.assigned_to
     WHERE l.tenant_id = p_tenant_id
       AND (p_visible_to IS NULL OR l.assigned_to = p_visible_to)
       AND (COALESCE(p_include_inactive, false) OR l.is_active)
       AND (NOT COALESCE(p_open_only, false) OR NOT l.is_closed)
       AND (p_status_id IS NULL OR l.lead_status_id = p_status_id)
       AND (p_source_id IS NULL OR l.lead_source_id = p_source_id)
       AND (p_assigned_to IS NULL OR l.assigned_to = p_assigned_to)
       AND (p_follow_up IS NULL OR (NOT l.is_closed AND l.next_follow_up_date IS NOT NULL AND CASE p_follow_up
            WHEN 'today' THEN l.next_follow_up_date = fn_business_today(p_tenant_id) WHEN 'overdue' THEN l.next_follow_up_date < fn_business_today(p_tenant_id)
            ELSE l.next_follow_up_date <= fn_business_today(p_tenant_id) END))
       AND (p_search IS NULL OR btrim(p_search) = ''
            OR position(lower(btrim(p_search)) IN lower(l.lead_no || ' ' || l.lead_name || ' ' || l.mobile)) > 0)
       AND (p_from IS NULL OR l.created_at >= fn_business_day_start(p_tenant_id, p_from))
       AND (p_to IS NULL OR l.created_at < fn_business_day_start(p_tenant_id, p_to + 1))
       AND (p_closed_since IS NULL OR (l.is_closed AND l.closed_at >= fn_business_day_start(p_tenant_id, p_closed_since)))
     ORDER BY l.created_at DESC, l.lead_id DESC
     LIMIT p_limit OFFSET COALESCE(p_offset, 0);
END;
$$;
