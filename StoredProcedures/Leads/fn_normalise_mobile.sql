-- The one stored form of an Indian mobile number, the same reduction the API's MobileNumber.Normalize does and that
-- customers use: spaces and dashes (including the dashes a word processor types) are removed, then a +91, a bare 91
-- (only on a 12-digit number) or a leading 0 is stripped, but only when exactly ten digits remain, so a number that
-- is wrong stays recognisably wrong. The result may still be invalid; ck_leads_mobile and the callers check it
-- (ten digits, the first 6-9). Every duplicate check on a lead compares numbers in this form.
CREATE OR REPLACE FUNCTION fn_normalise_mobile(p_raw text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    c_ten_digits CONSTANT text := '^[0-9]{10}$';
    v_compact    text := regexp_replace(COALESCE(p_raw, ''), '[[:space:]‐‑‒–—-]', '', 'g');
BEGIN
    IF left(v_compact, 3) = '+91' AND substr(v_compact, 4) ~ c_ten_digits THEN
        RETURN substr(v_compact, 4);
    END IF;
    IF length(v_compact) = 12 AND left(v_compact, 2) = '91' AND substr(v_compact, 3) ~ c_ten_digits THEN
        RETURN substr(v_compact, 3);
    END IF;
    IF left(v_compact, 1) = '0' AND substr(v_compact, 2) ~ c_ten_digits THEN
        RETURN substr(v_compact, 2);
    END IF;
    RETURN v_compact;
END;
$$;
