-- Report: ticket resolution time by issue type over the tickets CREATED in the range (business days; both missing = the current month; at most
-- 366 days). p_issue_type_id limits it to one type (a ticket with free-text "Other" has no type and is reported as "Other"). One row per type plus a
-- final TOTAL row (is_total).
--   resolved   tickets that have been resolved (resolved_at is set); unresolved = tickets that have not: still open, or closed without work.
--   avg_hours / max_hours   creation to resolution, over the RESOLVED tickets only (unresolved ones are counted apart, never in the averages)
--   within_48h / within_48h_share   resolved within 48 hours, and that as a percentage of the resolved ones (0 when none were resolved)
--   22023 invalid parameter - a bad range (COLUMN from or to)
CREATE OR REPLACE FUNCTION fn_report_ticket_resolution(p_tenant_id integer, p_from date, p_to date, p_issue_type_id integer DEFAULT NULL)
RETURNS TABLE (issue_type_id integer, issue_text varchar, tickets bigint, resolved bigint, unresolved bigint, avg_hours numeric,
               max_hours numeric, within_48h bigint, within_48h_share numeric, is_total boolean)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    c_quick_hours CONSTANT integer := 48;
    v_from date;
    v_to   date;
BEGIN
    SELECT r.range_from, r.range_to INTO v_from, v_to FROM fn_resolve_report_range(p_tenant_id, p_from, p_to) r;
    RETURN QUERY
    WITH t AS (
        SELECT v.issue_type_id, CASE WHEN v.issue_type_id IS NULL THEN 'Other' ELSE v.issue_text END AS issue_text, v.hours_to_resolve
          FROM vw_ticket_summary v
         WHERE v.tenant_id = p_tenant_id AND v.created_date BETWEEN v_from AND v_to AND (p_issue_type_id IS NULL OR v.issue_type_id = p_issue_type_id)
    ), g AS (
        SELECT t.issue_type_id, min(t.issue_text) AS issue_text, count(*) AS tickets, count(t.hours_to_resolve) AS resolved,
               round(avg(t.hours_to_resolve)::numeric, 1) AS avg_hours, round(max(t.hours_to_resolve)::numeric, 1) AS max_hours,
               count(*) FILTER (WHERE t.hours_to_resolve <= c_quick_hours) AS within
          FROM t GROUP BY t.issue_type_id
    )
    SELECT g.issue_type_id, g.issue_text::varchar, g.tickets, g.resolved, g.tickets - g.resolved, g.avg_hours, g.max_hours, g.within,
           fn_conversion_pct(g.within, g.resolved), false FROM g
    UNION ALL
    SELECT NULL::integer, 'All issue types'::varchar, count(*), count(t.hours_to_resolve), count(*) - count(t.hours_to_resolve),
           round(avg(t.hours_to_resolve)::numeric, 1), round(max(t.hours_to_resolve)::numeric, 1),
           count(*) FILTER (WHERE t.hours_to_resolve <= c_quick_hours),
           fn_conversion_pct(count(*) FILTER (WHERE t.hours_to_resolve <= c_quick_hours), count(t.hours_to_resolve)), true FROM t
    ORDER BY 10, 2;
END;
$$;
