-- A report covers one range of days, at most 366. Used by the three report functions; the API checks the same first.
--   22023 invalid parameter - a missing day, an end before the start, or more than 366 days (COLUMN from or to)
CREATE OR REPLACE FUNCTION fn_check_report_range(p_from date, p_to date)
RETURNS void
LANGUAGE plpgsql STABLE AS $$
DECLARE
    c_max_days CONSTANT integer := 366;
BEGIN
    IF p_from IS NULL THEN
        RAISE EXCEPTION 'Give the first day of the report' USING ERRCODE = '22023', COLUMN = 'from';
    END IF;
    IF p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'The end date cannot be before the start date' USING ERRCODE = '22023', COLUMN = 'to';
    END IF;
    IF p_to - p_from + 1 > c_max_days THEN
        RAISE EXCEPTION 'A report covers at most % days', c_max_days USING ERRCODE = '22023', COLUMN = 'to';
    END IF;
END;
$$;
