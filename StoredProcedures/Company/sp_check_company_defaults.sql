-- The default quotation texts of the profile document: defaultPaymentTermsHtml and defaultTermsHtml (restricted HTML, up to 20,000 characters: see
-- fn_html_is_allowed) and defaultCostNotes (up to 1000 characters). Each is optional.
--   22023 invalid parameter - the first field that is wrong (COLUMN names it)
CREATE OR REPLACE PROCEDURE sp_check_company_defaults(p_profile jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    v_key text;
BEGIN
    FOREACH v_key IN ARRAY ARRAY['defaultPaymentTermsHtml', 'defaultTermsHtml'] LOOP
        IF length(p_profile ->> v_key) > 20000 OR NOT fn_html_is_allowed(p_profile ->> v_key) THEN
            RAISE EXCEPTION 'The text is too long or uses formatting that is not allowed (only bold, italic, headings, bullets and numbered lists)'
                USING ERRCODE = '22023', COLUMN = v_key;
        END IF;
    END LOOP;
    CALL sp_assert_company_text(p_profile, 'defaultCostNotes', 1000);
END;
$$;
