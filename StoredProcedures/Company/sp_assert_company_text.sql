-- Checks that one text field of the profile document is at most p_max characters (a blank is fine: it is stored as NULL).
--   22023 invalid parameter - too long (COLUMN is the request field, for example 'legalName')
CREATE OR REPLACE PROCEDURE sp_assert_company_text(p_profile jsonb, p_key text, p_max integer)
LANGUAGE plpgsql AS $$
BEGIN
    IF length(fn_company_value(p_profile, p_key)) > p_max THEN
        RAISE EXCEPTION 'Must be % characters or fewer', p_max USING ERRCODE = '22023', COLUMN = p_key;
    END IF;
END;
$$;
