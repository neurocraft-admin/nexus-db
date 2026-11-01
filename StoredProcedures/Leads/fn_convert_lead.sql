-- Turns a lead into a customer in ONE transaction and returns the customer id. The customer is found by the lead's
-- mobile number or created from the lead; the lead is linked to it and becomes Won; one 'converted' history row says
-- what happened (the old and new status, and whether the customer was created or already existed); and the lead's
-- quotations that have no customer get this one (sp_fill_lead_quotations, with an audit row each). If any step
-- fails, nothing is kept.
-- Safe to repeat: the lead row is locked first, so two simultaneous conversions queue up, and a lead that is already
-- converted just returns its customer (no new customer, no second history row).
-- A staff user (p_visible_to is their id) can only convert a lead assigned to them.
--   P0002 not found     - unknown lead or one outside p_visible_to
--   NX409 rule conflict - a deactivated lead; a Lost lead (reopen it first); a deactivated customer holding the
--                         mobile; no active Won status configured
CREATE OR REPLACE FUNCTION fn_convert_lead(p_tenant_id integer, p_lead_id bigint, p_user_id integer, p_visible_to integer)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_lead     record;
    v_won      record;
    v_customer bigint;
    v_created  boolean;
    v_old_name varchar;
BEGIN
    -- Locked on the lead alone (see sp_change_lead_status): a join to the status would make a waiting caller lose the row.
    SELECT l.lead_no, l.lead_name, l.mobile, l.address, l.converted_customer_id, l.is_active, l.lead_status_id INTO v_lead
      FROM leads l
     WHERE l.lead_id = p_lead_id AND l.tenant_id = p_tenant_id AND (p_visible_to IS NULL OR l.assigned_to = p_visible_to)
       FOR UPDATE OF l;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lead % not found', p_lead_id USING ERRCODE = 'P0002';
    END IF;
    IF v_lead.converted_customer_id IS NOT NULL THEN
        RETURN v_lead.converted_customer_id;
    END IF;
    IF NOT v_lead.is_active OR EXISTS (SELECT 1 FROM lead_statuses s WHERE s.lead_status_id = v_lead.lead_status_id AND s.is_lost) THEN
        RAISE EXCEPTION 'A deactivated or lost lead cannot be converted; reopen it first' USING ERRCODE = 'NX409';
    END IF;
    SELECT s.status_name INTO v_old_name FROM lead_statuses s WHERE s.lead_status_id = v_lead.lead_status_id;
    SELECT s.lead_status_id, s.status_name INTO v_won FROM lead_statuses s
     WHERE s.tenant_id = p_tenant_id AND s.is_won AND s.is_active ORDER BY s.sort_order, s.lead_status_id LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No Won status is configured' USING ERRCODE = 'NX409';
    END IF;
    CALL sp_find_or_create_customer(p_tenant_id, v_lead.lead_name, v_lead.mobile, v_lead.address, v_customer, v_created);
    UPDATE leads SET converted_customer_id = v_customer, converted_at = now(), lead_status_id = v_won.lead_status_id,
           is_closed = true, closed_at = now(), lost_reason = NULL, updated_at = now()
     WHERE leads.lead_id = p_lead_id AND leads.tenant_id = p_tenant_id;
    CALL sp_log_lead_activity(p_tenant_id, p_lead_id, 'converted', v_old_name, v_won.status_name,
                              CASE WHEN v_created THEN 'Customer created' ELSE 'Linked to an existing customer' END, p_user_id);
    CALL sp_fill_lead_quotations(p_tenant_id, p_lead_id, v_customer, p_user_id, v_lead.lead_no);
    RETURN v_customer;
END;
$$;
