-- A plain decimal number (digits with an optional single decimal point, no sign, no exponent, no thousands
-- separators), or NULL when the text is not one. Used to check import rows without raising for the whole file.
CREATE OR REPLACE FUNCTION fn_try_numeric(p_text text)
RETURNS numeric
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_text IS NULL OR p_text !~ '^[0-9]{1,15}(\.[0-9]{1,6})?$' THEN
        RETURN NULL;
    END IF;
    RETURN p_text::numeric;
END;
$$;
