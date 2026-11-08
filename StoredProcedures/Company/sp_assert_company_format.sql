-- Checks that one field of the profile document, when given, matches a pattern. With p_upper the value is compared in
-- upper case (GSTIN, PAN and IFSC are stored upper-cased, so typing them in lower case is fine).
--   22023 invalid parameter - the value does not match (COLUMN is the request field; the message says what is expected)
CREATE OR REPLACE PROCEDURE sp_assert_company_format(
    p_profile jsonb, p_key text, p_pattern text, p_message text, p_upper boolean DEFAULT false)
LANGUAGE plpgsql AS $$
DECLARE
    v_value text := fn_company_value(p_profile, p_key);
BEGIN
    IF p_upper THEN
        v_value := upper(v_value);
    END IF;
    IF v_value IS NOT NULL AND v_value !~ p_pattern THEN
        RAISE EXCEPTION '%', p_message USING ERRCODE = '22023', COLUMN = p_key;
    END IF;
END;
$$;
