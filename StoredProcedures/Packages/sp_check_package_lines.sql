-- Validates the lines of a package and locks the items they name. p_lines is a JSON array of
-- {"itemId": 1, "quantity": 2.5}. Item rows are locked FOR UPDATE in item_id order (the same order purchases use),
-- so concurrent saves cannot deadlock. Each RAISE names the request field with COLUMN.
--   22023 invalid parameter - no lines, more than 100, a missing id, a quantity not above zero or with more than
--                             3 decimals, or an item twice
--   P0002 not found         - an item that does not exist (the message lists the missing ids)
--   NX409 rule conflict     - an inactive item: replace it before saving
CREATE OR REPLACE PROCEDURE sp_check_package_lines(p_tenant_id integer, p_lines jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    c_max_lines CONSTANT integer := 100;
    v_locked integer := 0;
    v_item   record;
BEGIN
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) NOT BETWEEN 1 AND c_max_lines THEN
        RAISE EXCEPTION 'A package needs between 1 and % lines', c_max_lines USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint, quantity numeric)
                WHERE l."itemId" IS NULL OR l."itemId" <= 0 OR l.quantity IS NULL OR l.quantity <= 0
                   OR l.quantity <> round(l.quantity, 3)) THEN
        RAISE EXCEPTION 'Each line needs an item and a quantity above zero with at most 3 decimals'
            USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
    IF (SELECT count(DISTINCT l."itemId") FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint))
           <> jsonb_array_length(p_lines) THEN
        RAISE EXCEPTION 'An item can appear only once in a package' USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
    FOR v_item IN
        SELECT i.item_code, i.is_active FROM items i
         WHERE i.tenant_id = p_tenant_id
           AND i.item_id IN (SELECT l."itemId" FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint))
         ORDER BY i.item_id
           FOR UPDATE
    LOOP
        v_locked := v_locked + 1;
        IF NOT v_item.is_active THEN
            RAISE EXCEPTION 'Item % is inactive; replace it', v_item.item_code USING ERRCODE = 'NX409', COLUMN = 'lines';
        END IF;
    END LOOP;
    IF v_locked <> jsonb_array_length(p_lines) THEN
        RAISE EXCEPTION 'One or more items were not found: %', fn_missing_item_ids(p_tenant_id, p_lines)
            USING ERRCODE = 'P0002', COLUMN = 'lines';
    END IF;
END;
$$;
