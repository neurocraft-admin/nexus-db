-- Checks the filters of the task list, so a mistyped one is an error and not an empty list.
--   22023 invalid parameter - an unknown status (COLUMN status; 'open' means assigned and in progress together), an unknown type
--                             (COLUMN taskType), or an end date before the start date (COLUMN to)
CREATE OR REPLACE PROCEDURE sp_check_task_filters(p_status varchar, p_task_type varchar, p_from date, p_to date)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_status IS NOT NULL AND p_status NOT IN ('assigned', 'in_progress', 'done', 'cancelled', 'open') THEN
        RAISE EXCEPTION 'Unknown task status' USING ERRCODE = '22023', COLUMN = 'status';
    END IF;
    IF p_task_type IS NOT NULL AND p_task_type NOT IN ('installation', 'site_visit', 'service', 'other') THEN
        RAISE EXCEPTION 'Unknown task type' USING ERRCODE = '22023', COLUMN = 'taskType';
    END IF;
    IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_to < p_from THEN
        RAISE EXCEPTION 'The end date cannot be before the start date' USING ERRCODE = '22023', COLUMN = 'to';
    END IF;
END;
$$;
