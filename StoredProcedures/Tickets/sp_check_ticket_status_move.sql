-- The ticket lifecycle, in one place. Allowed moves:
--   open -> in_progress          in_progress -> resolved
--   resolved -> closed           resolved -> in_progress   (reopen: from Resolved only)
--   open -> closed               (rare, and it needs a note)
-- Everything else is refused: closed is final, and a ticket cannot skip a step or stay where it is.
--   22023 invalid parameter - an unknown new status (COLUMN status); a note over 500 characters, or no note on
--                             open -> closed (COLUMN note)
--   NX409 rule conflict     - a move that is not in the list above (COLUMN status)
CREATE OR REPLACE PROCEDURE sp_check_ticket_status_move(p_old_status varchar, p_new_status varchar, p_note varchar)
LANGUAGE plpgsql AS $$
DECLARE
    c_note_max CONSTANT integer := 500;
    c_moves    CONSTANT text[] := ARRAY['open>in_progress', 'in_progress>resolved', 'resolved>closed', 'resolved>in_progress', 'open>closed'];
    v_note     varchar := NULLIF(btrim(p_note), '');
BEGIN
    IF p_new_status IS NULL OR p_new_status NOT IN ('open', 'in_progress', 'resolved', 'closed') THEN
        RAISE EXCEPTION 'Unknown ticket status' USING ERRCODE = '22023', COLUMN = 'status';
    END IF;
    IF length(v_note) > c_note_max THEN
        RAISE EXCEPTION 'A note can be up to % characters', c_note_max USING ERRCODE = '22023', COLUMN = 'note';
    END IF;
    IF p_old_status = 'closed' THEN
        RAISE EXCEPTION 'A closed ticket cannot be changed' USING ERRCODE = 'NX409', COLUMN = 'status';
    END IF;
    IF p_old_status = p_new_status THEN
        RAISE EXCEPTION 'The ticket is already %', replace(p_new_status, '_', ' ') USING ERRCODE = 'NX409', COLUMN = 'status';
    END IF;
    IF NOT (p_old_status || '>' || p_new_status) = ANY (c_moves) THEN
        RAISE EXCEPTION 'A ticket cannot go from % to %', replace(p_old_status, '_', ' '), replace(p_new_status, '_', ' ')
            USING ERRCODE = 'NX409', COLUMN = 'status';
    END IF;
    IF p_old_status = 'open' AND p_new_status = 'closed' AND v_note IS NULL THEN
        RAISE EXCEPTION 'A note is needed to close a ticket that is still open' USING ERRCODE = '22023', COLUMN = 'note';
    END IF;
END;
$$;
