-- Validates the lines of a purchase and locks the items it will change. p_lines is a JSON array of
-- {"itemId": 1, "quantity": 2.5, "unitCost": 10.00}. Item rows are locked FOR UPDATE in item_id order, so two
-- purchases that share items cannot deadlock by locking them in a different order. Called inside
-- sp_record_purchase's transaction.
--   22023 invalid parameter - no lines, a missing or non-positive quantity, a negative cost, more than 3
--                             decimals of quantity or more than 2 of unit cost, or an item twice
--   P0002 not found         - an item that does not exist
--   NX409 rule conflict     - an inactive item
CREATE OR REPLACE PROCEDURE sp_check_purchase_lines(p_tenant_id integer, p_lines jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    v_locked integer := 0;
    v_item   record;
BEGIN
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
        RAISE EXCEPTION 'A purchase needs at least one line' USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint, quantity numeric, "unitCost" numeric)
                WHERE l."itemId" IS NULL OR l.quantity IS NULL OR l.quantity <= 0
                   OR l."unitCost" IS NULL OR l."unitCost" < 0) THEN
        RAISE EXCEPTION 'Each line needs an item, a quantity above zero and a cost of zero or more'
            USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint, quantity numeric, "unitCost" numeric)
                WHERE l.quantity <> round(l.quantity, 3) OR l."unitCost" <> round(l."unitCost", 2)) THEN
        RAISE EXCEPTION 'Quantity can have at most 3 decimals and unit cost at most 2' USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
    IF (SELECT count(DISTINCT l."itemId") FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint)) <> jsonb_array_length(p_lines) THEN
        RAISE EXCEPTION 'An item can appear only once in a purchase' USING ERRCODE = '22023', COLUMN = 'lines';
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
            RAISE EXCEPTION 'Item % is inactive', v_item.item_code USING ERRCODE = 'NX409', COLUMN = 'lines';
        END IF;
    END LOOP;
    IF v_locked <> jsonb_array_length(p_lines) THEN
        RAISE EXCEPTION 'One or more items were not found: %', (
            SELECT string_agg(l."itemId"::text, ', ' ORDER BY l."itemId")
              FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint)
             WHERE NOT EXISTS (SELECT 1 FROM items i WHERE i.tenant_id = p_tenant_id AND i.item_id = l."itemId"))
            USING ERRCODE = 'P0002', COLUMN = 'lines';
    END IF;
END;
$$;
