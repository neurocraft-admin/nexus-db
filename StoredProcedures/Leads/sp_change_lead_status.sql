-- Moves a lead to another pipeline status and writes exactly ONE 'status_change' history row (old and new status
-- names; for Lost, the reason too). Moving to the status the lead is already in changes nothing and writes nothing.
--   * Won is reached only by fn_convert_lead (a lead that has not become a customer is not Won); a converted lead
--     stays Won.
--   * Lost needs a short reason (p_lost_reason, up to 250 characters): it is kept on the lead and in the history.
--   * Moving a Lost lead to an open status reopens it, and is refused while another open lead has its mobile.
-- A staff user (p_visible_to is their id) can only change a lead assigned to them; any other lead is not found.
--   22023 invalid parameter - Lost without a reason, or a reason over 250 characters (COLUMN lostReason)
--   P0002 not found         - unknown lead or one outside p_visible_to; unknown status (COLUMN statusId)
--   NX409 rule conflict     - Won by hand; a converted lead; a deactivated lead or status; a reopen that would
--                             duplicate an open lead's mobile
CREATE OR REPLACE PROCEDURE sp_change_lead_status(
    p_tenant_id integer, p_lead_id bigint, p_status_id integer, p_lost_reason varchar, p_user_id integer,
    p_visible_to integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_lead   record;
    v_new    record;
    v_old_name varchar;
    v_reason varchar := NULLIF(btrim(p_lost_reason), '');
BEGIN
    -- The lock is taken on the lead alone: joined to the status, a waiting caller re-checks the join against the
    -- old status once the first caller has changed it, and wrongly finds nothing.
    SELECT l.lead_status_id, l.mobile, l.is_active, l.is_closed, l.converted_customer_id INTO v_lead
      FROM leads l
     WHERE l.lead_id = p_lead_id AND l.tenant_id = p_tenant_id AND (p_visible_to IS NULL OR l.assigned_to = p_visible_to)
       FOR UPDATE OF l;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lead % not found', p_lead_id USING ERRCODE = 'P0002';
    END IF;
    SELECT s.status_name INTO v_old_name FROM lead_statuses s WHERE s.lead_status_id = v_lead.lead_status_id;
    SELECT s.status_name, s.is_won, s.is_lost, s.is_active INTO v_new
      FROM lead_statuses s WHERE s.lead_status_id = p_status_id AND s.tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Status % not found', p_status_id USING ERRCODE = 'P0002', COLUMN = 'statusId';
    END IF;
    IF v_lead.lead_status_id = p_status_id THEN
        RETURN;
    END IF;
    CALL sp_check_lead_status_move(v_lead.is_active, v_lead.converted_customer_id IS NOT NULL, v_new.is_active, v_new.is_won, v_new.is_lost, v_reason);
    IF v_lead.is_closed AND NOT v_new.is_lost THEN
        CALL sp_assert_no_open_lead_mobile(p_tenant_id, v_lead.mobile, p_lead_id, p_visible_to);
    END IF;
    UPDATE leads SET lead_status_id = p_status_id, is_closed = v_new.is_lost, lost_reason = CASE WHEN v_new.is_lost THEN v_reason END,
           closed_at = CASE WHEN v_new.is_lost THEN now() END, updated_at = now()
     WHERE leads.lead_id = p_lead_id AND leads.tenant_id = p_tenant_id;
    CALL sp_log_lead_activity(p_tenant_id, p_lead_id, 'status_change', v_old_name, v_new.status_name, v_reason, p_user_id);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'An open lead already has this mobile number' USING ERRCODE = 'NX409', COLUMN = 'mobile';
END;
$$;
