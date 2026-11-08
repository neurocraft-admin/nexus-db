-- Validates the typed fields of a lead before it is saved. p_mobile must already be normalised (fn_normalise_mobile).
-- Each RAISE names the request field with COLUMN. The API checks the same things first; these are the safety net.
--   22023 invalid parameter - a missing or over-long name (leadName), a mobile that is not ten digits starting 6-9
--                             (mobile), a badly shaped or over-long email (email), an over-long address or notes, a
--                             value that is negative or has more than 2 decimals (expectedValue)
--   P0002 not found         - an unknown source (leadSourceId)
--   NX409 rule conflict     - a deactivated source
CREATE OR REPLACE PROCEDURE sp_check_lead_fields(
    p_tenant_id integer, p_lead_name varchar, p_mobile varchar, p_email varchar, p_address varchar,
    p_lead_source_id integer, p_expected_value numeric, p_notes varchar)
LANGUAGE plpgsql AS $$
DECLARE
    c_max_value CONSTANT numeric := 9999999999.99;
    v_active    boolean;
BEGIN
    IF p_lead_name IS NULL OR btrim(p_lead_name) = '' OR length(btrim(p_lead_name)) > 150 THEN
        RAISE EXCEPTION 'A lead needs a name of up to 150 characters' USING ERRCODE = '22023', COLUMN = 'leadName';
    END IF;
    IF p_mobile IS NULL OR p_mobile !~ '^[6-9][0-9]{9}$' THEN
        RAISE EXCEPTION 'Enter a 10-digit mobile number starting with 6, 7, 8 or 9' USING ERRCODE = '22023', COLUMN = 'mobile';
    END IF;
    IF p_email IS NOT NULL AND (length(p_email) > 150 OR p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') THEN
        RAISE EXCEPTION 'Enter a valid email address' USING ERRCODE = '22023', COLUMN = 'email';
    END IF;
    IF length(p_address) > 500 OR length(p_notes) > 2000 THEN
        RAISE EXCEPTION 'The address is up to 500 characters and the notes up to 2000' USING ERRCODE = '22023',
            COLUMN = CASE WHEN length(p_address) > 500 THEN 'address' ELSE 'notes' END;
    END IF;
    IF p_expected_value IS NOT NULL AND (p_expected_value < 0 OR p_expected_value > c_max_value OR p_expected_value <> round(p_expected_value, 2)) THEN
        RAISE EXCEPTION 'The expected value is 0 or more with at most 2 decimals' USING ERRCODE = '22023', COLUMN = 'expectedValue';
    END IF;
    SELECT s.is_active INTO v_active FROM lead_sources s WHERE s.lead_source_id = p_lead_source_id AND s.tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lead source % not found', p_lead_source_id USING ERRCODE = 'P0002', COLUMN = 'leadSourceId';
    END IF;
    IF NOT v_active THEN
        RAISE EXCEPTION 'That lead source is no longer in use' USING ERRCODE = 'NX409', COLUMN = 'leadSourceId';
    END IF;
END;
$$;
