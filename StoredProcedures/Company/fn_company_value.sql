-- One text field of the profile document, trimmed, with a blank turned into NULL (the profile stores "not given" as NULL,
-- never as an empty string). p_profile is the JSON the API sends; p_key is the request field name, for example 'gstin'.
CREATE OR REPLACE FUNCTION fn_company_value(p_profile jsonb, p_key text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT NULLIF(btrim(p_profile ->> p_key), '');
$$;
