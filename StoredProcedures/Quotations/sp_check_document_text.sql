-- Validates the TEXT keys of the document settings of a quotation or a template. p_document is a JSON object; a key that is missing is not checked
-- (and not changed by the save). Each RAISE names the request field with COLUMN.
--   documentTitle (250), costNotes (1000), paymentTermsHtml and termsHtml (20,000, restricted HTML: see fn_html_is_allowed)
--   22023 invalid parameter - not an object, a text too long, or HTML that breaks the allow-list
CREATE OR REPLACE PROCEDURE sp_check_document_text(p_document jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    c_html CONSTANT integer := 20000;
    v_key  text;
BEGIN
    IF p_document IS NULL OR jsonb_typeof(p_document) <> 'object' THEN
        RAISE EXCEPTION 'The document settings must be an object' USING ERRCODE = '22023', COLUMN = 'document';
    END IF;
    IF length(p_document ->> 'documentTitle') > 250 THEN
        RAISE EXCEPTION 'The title can have at most 250 characters' USING ERRCODE = '22023', COLUMN = 'documentTitle';
    END IF;
    IF length(p_document ->> 'costNotes') > 1000 THEN
        RAISE EXCEPTION 'The cost-page notes can have at most 1000 characters' USING ERRCODE = '22023', COLUMN = 'costNotes';
    END IF;
    FOREACH v_key IN ARRAY ARRAY['paymentTermsHtml', 'termsHtml'] LOOP
        IF length(p_document ->> v_key) > c_html OR NOT fn_html_is_allowed(p_document ->> v_key) THEN
            RAISE EXCEPTION 'The text is too long or uses formatting that is not allowed (only bold, italic, headings, bullets and numbered lists)'
                USING ERRCODE = '22023', COLUMN = v_key;
        END IF;
    END LOOP;
END;
$$;
