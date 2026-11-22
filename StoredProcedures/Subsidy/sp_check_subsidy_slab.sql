-- Validates one subsidy slab before it is saved. Each RAISE names the request field with COLUMN.
--   22023 invalid parameter - a bound or amount that is negative, has more than 2 decimals or is too large; an upper bound that is not above the
--                             lower one; a category that has no subsidy (none, commercial)
--   P0002 not found         - an unknown category
CREATE OR REPLACE PROCEDURE sp_check_subsidy_slab(
    p_tenant_id integer, p_category_code varchar, p_from numeric, p_to numeric, p_amount numeric)
LANGUAGE plpgsql AS $$
DECLARE
    c_max_kw CONSTANT numeric := 9999.99;
    v_has    boolean;
BEGIN
    SELECT c.has_subsidy INTO v_has FROM subsidy_categories c
     WHERE c.tenant_id = p_tenant_id AND c.category_code = p_category_code AND c.is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Subsidy category % not found', p_category_code USING ERRCODE = 'P0002', COLUMN = 'categoryCode';
    END IF;
    IF NOT v_has THEN
        RAISE EXCEPTION 'Category % has no subsidy, so it has no slabs', p_category_code USING ERRCODE = '22023', COLUMN = 'categoryCode';
    END IF;
    IF p_from IS NULL OR p_from < 0 OR p_from > c_max_kw OR p_from <> round(p_from, 2) THEN
        RAISE EXCEPTION 'The lower capacity must be 0 kW or more with at most 2 decimals' USING ERRCODE = '22023', COLUMN = 'capacityFromKw';
    END IF;
    IF p_to IS NOT NULL AND (p_to <= p_from OR p_to > c_max_kw OR p_to <> round(p_to, 2)) THEN
        RAISE EXCEPTION 'The upper capacity must be above the lower one (or empty for no upper limit)' USING ERRCODE = '22023', COLUMN = 'capacityToKw';
    END IF;
    IF p_amount IS NULL OR p_amount < 0 OR p_amount > 9999999999.99 OR p_amount <> round(p_amount, 2) THEN
        RAISE EXCEPTION 'The amount must be 0 or more with at most 2 decimals' USING ERRCODE = '22023', COLUMN = 'amount';
    END IF;
END;
$$;
