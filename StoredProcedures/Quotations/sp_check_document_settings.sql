-- Validates the document settings of a quotation or a template (the JSON p_document read by sp_save_quotation and sp_save_template): the text keys
-- (sp_check_document_text) and the others. A key that is missing is not checked and not changed by the save; a null value clears it.
--   capacityKw      a number above 0 with at most 2 decimals and under 10,000
--   subsidyCategory the code of an active subsidy category (null means none)
--   subsidyAmount   a number of 0 or more with at most 2 decimals, and not more than p_payable (the customer payable) when that is given;
--                   a template has no amount, so it passes NULL for p_payable and the key is ignored
--   showLinePrices  true or false
--   datasheetIds    an array of up to 20 different positive numbers (whether they exist is checked when the list is written)
--   22023 invalid parameter, P0002 unknown category. Each RAISE names the request field with COLUMN.
CREATE OR REPLACE PROCEDURE sp_check_document_settings(p_tenant_id integer, p_document jsonb, p_payable numeric)
LANGUAGE plpgsql AS $$
DECLARE
    c_max_sheets CONSTANT integer := 20;
    v_cap jsonb := p_document -> 'capacityKw';
    v_amt jsonb := p_document -> 'subsidyAmount';
    v_ids jsonb := p_document -> 'datasheetIds';
BEGIN
    CALL sp_check_document_text(p_document);
    IF jsonb_typeof(v_cap) = 'number' AND (v_cap::text::numeric <= 0 OR v_cap::text::numeric >= 10000 OR v_cap::text::numeric <> round(v_cap::text::numeric, 2))
       OR jsonb_typeof(v_cap) NOT IN ('number', 'null') THEN
        RAISE EXCEPTION 'The capacity must be above 0 kW and under 10,000 kW with at most 2 decimals' USING ERRCODE = '22023', COLUMN = 'capacityKw';
    END IF;
    IF jsonb_typeof(p_document -> 'showLinePrices') NOT IN ('boolean', 'null') THEN
        RAISE EXCEPTION 'Show line prices is true or false' USING ERRCODE = '22023', COLUMN = 'showLinePrices';
    END IF;
    IF p_document ? 'subsidyCategory' AND jsonb_typeof(p_document -> 'subsidyCategory') = 'string' AND NOT EXISTS (
           SELECT 1 FROM subsidy_categories c WHERE c.tenant_id = p_tenant_id AND c.is_active AND c.category_code = p_document ->> 'subsidyCategory') THEN
        RAISE EXCEPTION 'Subsidy category % not found', p_document ->> 'subsidyCategory' USING ERRCODE = 'P0002', COLUMN = 'subsidyCategory';
    END IF;
    IF p_payable IS NOT NULL AND jsonb_typeof(v_amt) = 'number' AND (v_amt::text::numeric < 0 OR v_amt::text::numeric <> round(v_amt::text::numeric, 2)
                                                                      OR v_amt::text::numeric > p_payable) THEN
        RAISE EXCEPTION 'The subsidy must be 0 or more with at most 2 decimals, and not more than the customer payable (%)', p_payable
            USING ERRCODE = '22023', COLUMN = 'subsidyAmount';
    END IF;
    IF v_ids IS NOT NULL AND jsonb_typeof(v_ids) <> 'null' AND (jsonb_typeof(v_ids) <> 'array' OR jsonb_array_length(v_ids) > c_max_sheets) THEN
        RAISE EXCEPTION 'Choose up to % datasheets', c_max_sheets USING ERRCODE = '22023', COLUMN = 'datasheetIds';
    END IF;
END;
$$;
