-- Refuses a mobile number that another OPEN lead already has (open = active and not Won or Lost). p_mobile must
-- already be in the stored form (fn_normalise_mobile). The message names the lead, so the person can find it, but only
-- when p_visible_to (a staff user's id; NULL for an admin) may see that lead: otherwise it says only that the mobile has
-- an open lead, so a staff user cannot learn the number of someone else's lead.
-- This is the friendly check; uq_leads_open_mobile is the guarantee when two people save at the same moment.
--   NX409 rule conflict - another open lead has this number (COLUMN mobile)
DROP PROCEDURE IF EXISTS sp_assert_no_open_lead_mobile(integer, varchar, bigint);
CREATE OR REPLACE PROCEDURE sp_assert_no_open_lead_mobile(
    p_tenant_id integer, p_mobile varchar, p_except_lead_id bigint, p_visible_to integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_lead_no varchar;
    v_seen    boolean;
BEGIN
    SELECT l.lead_no, (p_visible_to IS NULL OR l.assigned_to = p_visible_to) INTO v_lead_no, v_seen
      FROM leads l
     WHERE l.tenant_id = p_tenant_id AND l.mobile = p_mobile AND l.is_active AND NOT l.is_closed
       AND l.lead_id IS DISTINCT FROM p_except_lead_id
     LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION '%', CASE WHEN v_seen THEN format('An open lead (%s) already has this mobile number', v_lead_no)
                                  ELSE 'This mobile already has an open lead' END USING ERRCODE = 'NX409', COLUMN = 'mobile';
    END IF;
END;
$$;
