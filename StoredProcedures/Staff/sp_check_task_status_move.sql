-- The task lifecycle, in one place. Allowed moves:
--   assigned -> in_progress or cancelled      in_progress -> done or cancelled
-- done and cancelled are final; a task cannot stay where it is. Done needs a completion note.
--   22023 invalid parameter - an unknown new status (COLUMN status); a note over 500 characters, or no note on done (COLUMN note)
--   NX409 rule conflict     - a move that is not in the list above (COLUMN status)
CREATE OR REPLACE PROCEDURE sp_check_task_status_move(p_old_status varchar, p_new_status varchar, p_note varchar)
LANGUAGE plpgsql AS $$
DECLARE
    c_note_max CONSTANT integer := 500;
    c_moves    CONSTANT text[] := ARRAY['assigned>in_progress', 'assigned>cancelled', 'in_progress>done', 'in_progress>cancelled'];
    v_note     varchar := NULLIF(btrim(p_note), '');
BEGIN
    IF p_new_status IS NULL OR p_new_status NOT IN ('assigned', 'in_progress', 'done', 'cancelled') THEN
        RAISE EXCEPTION 'Unknown task status' USING ERRCODE = '22023', COLUMN = 'status';
    END IF;
    IF length(v_note) > c_note_max THEN
        RAISE EXCEPTION 'A note can be up to % characters', c_note_max USING ERRCODE = '22023', COLUMN = 'note';
    END IF;
    IF p_old_status IN ('done', 'cancelled') THEN
        RAISE EXCEPTION 'A % task cannot be changed', replace(p_old_status, '_', ' ') USING ERRCODE = 'NX409', COLUMN = 'status';
    END IF;
    IF p_old_status = p_new_status THEN
        RAISE EXCEPTION 'The task is already %', replace(p_new_status, '_', ' ') USING ERRCODE = 'NX409', COLUMN = 'status';
    END IF;
    IF NOT (p_old_status || '>' || p_new_status) = ANY (c_moves) THEN
        RAISE EXCEPTION 'A task cannot go from % to %', replace(p_old_status, '_', ' '), replace(p_new_status, '_', ' ')
            USING ERRCODE = 'NX409', COLUMN = 'status';
    END IF;
    IF p_new_status = 'done' AND v_note IS NULL THEN
        RAISE EXCEPTION 'A completion note is needed to finish a task' USING ERRCODE = '22023', COLUMN = 'note';
    END IF;
END;
$$;
