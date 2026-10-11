-- Removes stock for one item: one 'out' ledger row and current_stock down. Other modules call this (order
-- fulfilment); it does no transaction control, so a caller can fulfil several lines in one transaction and have
-- all of them roll back together if one is short. The item row is locked FOR UPDATE, so two simultaneous
-- stock-outs cannot both pass the check on the same quantity. unit_cost is the item's cost price at that moment.
--   P0002 not found         - unknown item
--   NX409 rule conflict     - the item is inactive
--   NX411 insufficient stock - stock would go below zero; the message names the item, what is available and
--                              what was asked for, so the caller can tell the person which line is short.
--                              The API maps NX411 to 409.
--   22023 invalid parameter - quantity not above zero
CREATE OR REPLACE PROCEDURE sp_stock_out(
    p_tenant_id integer, p_item_id bigint, p_quantity numeric,
    p_reference_type varchar, p_reference_id bigint, p_note varchar, p_created_by integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_code   varchar;
    v_active boolean;
    v_stock  numeric;
    v_cost   numeric;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be above zero' USING ERRCODE = '22023';
    END IF;

    SELECT i.item_code, i.is_active, i.current_stock, i.cost_price INTO v_code, v_active, v_stock, v_cost
      FROM items i
     WHERE i.item_id = p_item_id AND i.tenant_id = p_tenant_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item % not found', p_item_id USING ERRCODE = 'P0002';
    END IF;
    IF NOT v_active THEN
        RAISE EXCEPTION 'Item % is inactive', v_code USING ERRCODE = 'NX409';
    END IF;
    IF v_stock < p_quantity THEN
        RAISE EXCEPTION 'Insufficient stock for item %: available %, requested %', v_code, v_stock, p_quantity
            USING ERRCODE = 'NX411';
    END IF;

    INSERT INTO stock_movements (tenant_id, item_id, movement_type, quantity, signed_quantity, unit_cost,
                                 reference_type, reference_id, note, created_by)
    VALUES (p_tenant_id, p_item_id, 'out', p_quantity, -p_quantity, v_cost,
            p_reference_type, p_reference_id, p_note, p_created_by);

    UPDATE items
       SET current_stock = current_stock - p_quantity, updated_at = now()
     WHERE item_id = p_item_id AND tenant_id = p_tenant_id;
END;
$$;
