-- The rules for moving a lead to a status, apart from looking anything up (see sp_change_lead_status).
--   NX409 rule conflict - the lead is deactivated; the lead is converted (it stays Won); the status is retired;
--                         the status is Won (only converting makes a lead Won)
--   22023 invalid parameter - Lost without a reason, or a reason over 250 characters (COLUMN lostReason)
CREATE OR REPLACE PROCEDURE sp_check_lead_status_move(
    p_lead_is_active boolean, p_lead_is_converted boolean, p_status_is_active boolean, p_status_is_won boolean,
    p_status_is_lost boolean, p_lost_reason varchar)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT p_lead_is_active THEN
        RAISE EXCEPTION 'A deactivated lead cannot change status' USING ERRCODE = 'NX409';
    END IF;
    IF p_lead_is_converted THEN
        RAISE EXCEPTION 'A converted lead stays Won' USING ERRCODE = 'NX409';
    END IF;
    IF NOT p_status_is_active THEN
        RAISE EXCEPTION 'That status is no longer in use' USING ERRCODE = 'NX409', COLUMN = 'statusId';
    END IF;
    IF p_status_is_won THEN
        RAISE EXCEPTION 'A lead becomes Won only by converting it to a customer' USING ERRCODE = 'NX409', COLUMN = 'statusId';
    END IF;
    IF p_status_is_lost AND p_lost_reason IS NULL THEN
        RAISE EXCEPTION 'Say why the lead was lost' USING ERRCODE = '22023', COLUMN = 'lostReason';
    END IF;
    IF length(p_lost_reason) > 250 THEN
        RAISE EXCEPTION 'The reason is up to 250 characters' USING ERRCODE = '22023', COLUMN = 'lostReason';
    END IF;
END;
$$;
