-- Validates the whole profile document before anything is saved. Every field is optional; a given field must fit its
-- column and its format (the table's CHECKs are the safety net behind these, with the same patterns). All the fields are
-- request names (camelCase) so the API can show each message next to its field.
--   22023 invalid parameter - the first field that is wrong (COLUMN names it)
CREATE OR REPLACE PROCEDURE sp_check_company_profile(p_profile jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    c_gstin   CONSTANT text := '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$';
    v_gstin   text := upper(fn_company_value(p_profile, 'gstin'));
    v_state   text := fn_company_value(p_profile, 'stateCode');
BEGIN
    CALL sp_assert_company_text(p_profile, 'legalName', 200);
    CALL sp_assert_company_text(p_profile, 'displayName', 150);
    CALL sp_assert_company_text(p_profile, 'tagline', 200);
    CALL sp_assert_company_text(p_profile, 'addressLine1', 200);
    CALL sp_assert_company_text(p_profile, 'addressLine2', 200);
    CALL sp_assert_company_text(p_profile, 'city', 100);
    CALL sp_assert_company_text(p_profile, 'stateName', 100);
    CALL sp_assert_company_format(p_profile, 'pincode', '^[0-9]{6}$', 'A pincode is 6 digits');
    CALL sp_assert_company_text(p_profile, 'phone', 20);
    CALL sp_assert_company_text(p_profile, 'alternatePhone', 20);
    CALL sp_assert_company_text(p_profile, 'email', 150);
    CALL sp_assert_company_format(p_profile, 'email', '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$', 'Enter a valid email address');
    CALL sp_assert_company_text(p_profile, 'website', 200);
    CALL sp_assert_company_format(p_profile, 'website', '^https://[^[:space:]]+$', 'A website address starts with https://');
    CALL sp_assert_company_format(p_profile, 'gstin', c_gstin, 'A GSTIN is 15 characters, for example 32ABCDE1234F1Z5', true);
    CALL sp_assert_company_format(p_profile, 'pan', '^[A-Z]{5}[0-9]{4}[A-Z]$', 'A PAN is 5 letters, 4 digits and a letter', true);
    CALL sp_assert_company_format(p_profile, 'stateCode', '^[0-9]{2}$', 'A state code is 2 digits');
    IF v_gstin IS NOT NULL AND v_state IS NOT NULL AND left(v_gstin, 2) <> v_state THEN
        RAISE EXCEPTION 'The state code must match the first two digits of the GSTIN (%)', left(v_gstin, 2)
            USING ERRCODE = '22023', COLUMN = 'stateCode';
    END IF;
    CALL sp_check_company_bank(p_profile);
    CALL sp_assert_company_text(p_profile, 'quotationFooterNote', 1000);
    CALL sp_assert_company_text(p_profile, 'quotationTerms', 4000);
END;
$$;
