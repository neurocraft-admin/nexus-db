-- One lead's detail (its history is fn_get_lead_activities). No rows when the lead does not exist, belongs to another
-- tenant, or is not visible to this user: a staff user (p_visible_to is their id) gets nothing for a lead assigned to
-- someone else, the same as for a lead that does not exist, so the API answers 404 for both. (Today is worked out
-- inline, not with fn_business_today: SQL functions are checked when created and the Quotations folder applies later.)
CREATE OR REPLACE FUNCTION fn_get_lead_by_id(p_tenant_id integer, p_lead_id bigint, p_visible_to integer)
RETURNS TABLE (lead_id bigint, lead_no varchar, lead_name varchar, mobile varchar, email varchar, address varchar,
               lead_source_id integer, source_name varchar, lead_status_id integer, status_name varchar, is_won boolean,
               is_lost boolean, assigned_to integer, assigned_to_name varchar, expected_value numeric,
               next_follow_up_date date, is_overdue boolean, notes varchar, lost_reason varchar,
               converted_customer_id bigint, converted_customer_name varchar, converted_at timestamptz,
               external_ref varchar, source_detail varchar, import_batch_id bigint, created_by integer,
               created_by_name varchar, is_active boolean, is_closed boolean, closed_at timestamptz,
               created_at timestamptz, updated_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT l.lead_id, l.lead_no, l.lead_name, l.mobile, l.email, l.address, l.lead_source_id, s.source_name,
           l.lead_status_id, st.status_name, st.is_won, st.is_lost, l.assigned_to, a.full_name, l.expected_value,
           l.next_follow_up_date,
           COALESCE(NOT l.is_closed AND l.is_active AND l.next_follow_up_date < (now() AT TIME ZONE COALESCE(fn_get_setting(p_tenant_id, 'business_time_zone'), 'UTC'))::date, false), l.notes,
           l.lost_reason, l.converted_customer_id, c.customer_name, l.converted_at, l.external_ref, l.source_detail,
           l.import_batch_id, l.created_by, cb.full_name, l.is_active, l.is_closed, l.closed_at, l.created_at, l.updated_at
      FROM leads l
      JOIN lead_sources s ON s.lead_source_id = l.lead_source_id
      JOIN lead_statuses st ON st.lead_status_id = l.lead_status_id
      LEFT JOIN users a ON a.user_id = l.assigned_to
      LEFT JOIN users cb ON cb.user_id = l.created_by
      LEFT JOIN customers c ON c.customer_id = l.converted_customer_id
     WHERE l.tenant_id = p_tenant_id AND l.lead_id = p_lead_id
       AND (p_visible_to IS NULL OR l.assigned_to = p_visible_to);
$$;
