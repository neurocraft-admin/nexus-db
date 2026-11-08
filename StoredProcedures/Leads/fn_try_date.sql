-- A date typed as yyyy-MM-dd (the only form an import accepts), or NULL when the text is not a real date. Used to
-- check import rows without letting one bad cell raise an error for the whole file.
CREATE OR REPLACE FUNCTION fn_try_date(p_text text)
RETURNS date
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_text IS NULL OR p_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
        RETURN NULL;
    END IF;
    RETURN p_text::date;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;     -- 2026-02-31 and the like: matches the shape but is not a date
END;
$$;
