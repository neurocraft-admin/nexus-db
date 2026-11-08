-- Checks the follow-up filter of the lead list.
--   22023 invalid parameter - anything but NULL, 'today', 'overdue' or 'due' (COLUMN followUp)
CREATE OR REPLACE PROCEDURE sp_check_lead_follow_up_filter(p_follow_up varchar)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_follow_up IS NOT NULL AND p_follow_up NOT IN ('today', 'overdue', 'due') THEN
        RAISE EXCEPTION 'followUp must be today, overdue or due' USING ERRCODE = '22023', COLUMN = 'followUp';
    END IF;
END;
$$;
