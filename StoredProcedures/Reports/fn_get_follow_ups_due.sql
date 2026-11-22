-- Open leads whose next follow-up day is today or earlier (business day), the longest overdue first, with how many there are in all
-- (total_count). days_overdue = days since the follow-up day (0 = due today). p_visible_to = a staff user's own leads (NULL = everyone's).
CREATE OR REPLACE FUNCTION fn_get_follow_ups_due(p_tenant_id integer, p_visible_to integer, p_limit integer, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (lead_id bigint, lead_no varchar, lead_name varchar, mobile varchar, source_name varchar, status_name varchar,
               next_follow_up_date date, days_overdue integer, total_count bigint)
LANGUAGE sql STABLE AS $$
    WITH today AS (SELECT fn_business_date_of(p_tenant_id, COALESCE(p_as_of, now())) AS day)
    SELECT v.lead_id, v.lead_no, v.lead_name, v.mobile, v.source_name, v.status_name, v.next_follow_up_date,
           t.day - v.next_follow_up_date, count(*) OVER ()
      FROM vw_lead_pipeline v CROSS JOIN today t
     WHERE v.tenant_id = p_tenant_id AND NOT v.is_closed AND v.next_follow_up_date <= t.day
       AND (p_visible_to IS NULL OR v.assigned_to = p_visible_to)
     ORDER BY v.next_follow_up_date, v.created_at, v.lead_id
     LIMIT p_limit;
$$;
