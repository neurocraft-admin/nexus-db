-- Adds a note, a follow-up date, or both to a lead and writes exactly ONE history row: 'follow_up' when a date is
-- given (the new date, and the note if any), otherwise 'note'. A follow-up date sets the lead's next_follow_up_date
-- and cannot be in the past (business time zone); an overdue date is what makes a lead overdue, so it is only ever
-- set to today or later. Closed (Won or Lost) leads can take notes but no follow-up. A staff user (p_visible_to is
-- their id) can only write on a lead assigned to them.
--   22023 invalid parameter - neither a note nor a date, a note over 2000 characters (COLUMN note), a past date
--                             (COLUMN followUpDate)
--   P0002 not found         - unknown lead or one outside p_visible_to
--   NX409 rule conflict     - a deactivated lead; a follow-up on a closed lead
CREATE OR REPLACE PROCEDURE sp_add_lead_note(
    p_tenant_id integer, p_lead_id bigint, p_note varchar, p_follow_up_date date, p_user_id integer, p_visible_to integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_lead record;
    v_note varchar := NULLIF(btrim(p_note), '');
BEGIN
    IF v_note IS NULL AND p_follow_up_date IS NULL THEN
        RAISE EXCEPTION 'Write a note or choose a follow-up date' USING ERRCODE = '22023', COLUMN = 'note';
    END IF;
    IF length(v_note) > 2000 THEN
        RAISE EXCEPTION 'A note is up to 2000 characters' USING ERRCODE = '22023', COLUMN = 'note';
    END IF;
    IF p_follow_up_date < fn_business_today(p_tenant_id) THEN
        RAISE EXCEPTION 'The follow-up date cannot be in the past' USING ERRCODE = '22023', COLUMN = 'followUpDate';
    END IF;
    SELECT l.is_active, l.is_closed INTO v_lead FROM leads l
     WHERE l.lead_id = p_lead_id AND l.tenant_id = p_tenant_id AND (p_visible_to IS NULL OR l.assigned_to = p_visible_to)
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lead % not found', p_lead_id USING ERRCODE = 'P0002';
    END IF;
    IF NOT v_lead.is_active OR (v_lead.is_closed AND p_follow_up_date IS NOT NULL) THEN
        RAISE EXCEPTION 'A deactivated lead takes no notes and a closed lead no follow-up' USING ERRCODE = 'NX409';
    END IF;
    IF p_follow_up_date IS NOT NULL THEN
        UPDATE leads SET next_follow_up_date = p_follow_up_date, updated_at = now() WHERE leads.lead_id = p_lead_id AND leads.tenant_id = p_tenant_id;
    END IF;
    CALL sp_log_lead_activity(p_tenant_id, p_lead_id, CASE WHEN p_follow_up_date IS NULL THEN 'note' ELSE 'follow_up' END,
                              NULL, p_follow_up_date::text, v_note, p_user_id);
END;
$$;
