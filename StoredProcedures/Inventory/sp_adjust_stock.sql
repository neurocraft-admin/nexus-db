-- Manual correction: one 'adjust' ledger row (positive or negative) and current_stock changed by the same
-- amount. A note is mandatory. The row records the item's current cost price, so set the item's cost price
-- before entering opening stock this way. An inactive item may be adjusted (to bring it to zero).
--   P0002 not found         - unknown item
--   NX411 insufficient stock - the adjustment would take stock below zero
--   22023 invalid parameter - change is null or zero, or the note is empty
CREATE OR REPLACE PROCEDURE sp_adjust_stock(
    p_tenant_id integer, p_item_id bigint, p_quantity_change numeric, p_note varchar, p_created_by integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_code  varchar;
    v_stock numeric;
    v_cost  numeric;
BEGIN
    IF p_quantity_change IS NULL OR p_quantity_change = 0 THEN
        RAISE EXCEPTION 'The adjustment cannot be zero' USING ERRCODE = '22023';
    END IF;
    IF length(btrim(coalesce(p_note, ''))) = 0 THEN
        RAISE EXCEPTION 'A note is required for a stock adjustment' USING ERRCODE = '22023';
    END IF;

    SELECT i.item_code, i.current_stock, i.cost_price INTO v_code, v_stock, v_cost
      FROM items i
     WHERE i.item_id = p_item_id AND i.tenant_id = p_tenant_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item % not found', p_item_id USING ERRCODE = 'P0002';
    END IF;
    IF v_stock + p_quantity_change < 0 THEN
        RAISE EXCEPTION 'Insufficient stock for item %: available %, requested %', v_code, v_stock, -p_quantity_change
            USING ERRCODE = 'NX411';
    END IF;

    INSERT INTO stock_movements (tenant_id, item_id, movement_type, quantity, signed_quantity, unit_cost,
                                 reference_type, reference_id, note, created_by)
    VALUES (p_tenant_id, p_item_id, 'adjust', abs(p_quantity_change), p_quantity_change, v_cost,
            'adjustment', NULL, btrim(p_note), p_created_by);

    UPDATE items
       SET current_stock = current_stock + p_quantity_change, updated_at = now()
     WHERE item_id = p_item_id AND tenant_id = p_tenant_id;
END;
$$;
