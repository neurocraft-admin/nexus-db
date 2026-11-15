-- Checks the status and source filters of the ticket list, so a mistyped one is an error and not an empty list.
--   22023 invalid parameter - an unknown status (COLUMN status) or source (COLUMN source)
CREATE OR REPLACE PROCEDURE sp_check_ticket_filters(p_status varchar, p_source varchar)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_status IS NOT NULL AND p_status NOT IN ('open', 'in_progress', 'resolved', 'closed', 'active') THEN
        RAISE EXCEPTION 'Unknown ticket status' USING ERRCODE = '22023', COLUMN = 'status';
    END IF;
    IF p_source IS NOT NULL AND p_source NOT IN ('portal', 'internal') THEN
        RAISE EXCEPTION 'Unknown ticket source' USING ERRCODE = '22023', COLUMN = 'source';
    END IF;
END;
$$;
