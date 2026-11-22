-- The Supervisor's headline numbers, company-wide: tickets waiting for someone and how many have waited over a day, open and overdue tickets
-- (ticket_overdue_days), tasks for today (today or earlier) and how many are overdue, how many people have nothing on today, the busiest
-- person, and low stock. technicians_idle counts people who can be given work and have no task for today and no open ticket.
CREATE OR REPLACE FUNCTION fn_get_operations_summary(p_tenant_id integer, p_as_of timestamptz DEFAULT NULL)
RETURNS TABLE (needs_assignment bigint, needs_assignment_over_day bigint, open_tickets bigint, overdue_tickets bigint, tasks_today bigint,
               overdue_tasks bigint, technicians_idle bigint, busiest_name varchar, busiest_items bigint, low_stock_count bigint,
               low_stock_below_half bigint)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    c_waiting_day CONSTANT interval := interval '1 day';
    v_now timestamptz := COALESCE(p_as_of, now());
BEGIN
    SELECT count(*) FILTER (WHERE v.is_open AND v.is_unassigned),
           count(*) FILTER (WHERE v.is_open AND v.is_unassigned AND v.created_at < v_now - c_waiting_day),
           count(*) FILTER (WHERE v.is_open),
           count(*) FILTER (WHERE v.is_open AND v.created_at < v_now - make_interval(days => fn_ticket_overdue_days(p_tenant_id)))
      INTO needs_assignment, needs_assignment_over_day, open_tickets, overdue_tickets
      FROM vw_ticket_summary v WHERE v.tenant_id = p_tenant_id;
    SELECT COALESCE(sum(w.tasks_today), 0), COALESCE(sum(w.overdue_tasks), 0), count(*) FILTER (WHERE w.items = 0)
      INTO tasks_today, overdue_tasks, technicians_idle FROM fn_get_technician_workload(p_tenant_id, p_as_of) w;
    SELECT w.full_name, w.items INTO busiest_name, busiest_items
      FROM fn_get_technician_workload(p_tenant_id, p_as_of) w ORDER BY w.items DESC, w.full_name LIMIT 1;
    busiest_items := COALESCE(busiest_items, 0);
    SELECT count(*) FILTER (WHERE i.is_low), count(*) FILTER (WHERE i.is_below_half) INTO low_stock_count, low_stock_below_half
      FROM vw_inventory_status i WHERE i.tenant_id = p_tenant_id;
    RETURN NEXT;
END;
$$;
