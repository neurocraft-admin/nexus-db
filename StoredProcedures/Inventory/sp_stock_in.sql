-- Adds stock for one item: one 'in' ledger row and current_stock up, in the caller's transaction. It does no
-- transaction control of its own, so sp_record_purchase (and later modules) can call it as one step of a larger
-- atomic change. The item row is locked FOR UPDATE so concurrent movements cannot overwrite each other.
--   P0002 not found         - unknown item
--   NX409 rule conflict     - the item is inactive
--   22023 invalid parameter - quantity not above zero, or unit cost negative
CREATE OR REPLACE PROCEDURE sp_stock_in(
    p_tenant_id integer, p_item_id bigint, p_quantity numeric, p_unit_cost numeric,
    p_reference_type varchar, p_reference_id bigint, p_note varchar, p_created_by integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_code   varchar;
    v_active boolean;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be above zero' USING ERRCODE = '22023', COLUMN = 'quantity';
    END IF;
    IF p_unit_cost IS NULL OR p_unit_cost < 0 THEN
        RAISE EXCEPTION 'Unit cost cannot be negative' USING ERRCODE = '22023', COLUMN = 'unitCost';
    END IF;

    SELECT i.item_code, i.is_active INTO v_code, v_active
      FROM items i
     WHERE i.item_id = p_item_id AND i.tenant_id = p_tenant_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item % not found', p_item_id USING ERRCODE = 'P0002', COLUMN = 'itemId';
    END IF;
    IF NOT v_active THEN
        RAISE EXCEPTION 'Item % is inactive', v_code USING ERRCODE = 'NX409', COLUMN = 'itemId';
    END IF;

    INSERT INTO stock_movements (tenant_id, item_id, movement_type, quantity, signed_quantity, unit_cost,
                                 reference_type, reference_id, note, created_by)
    VALUES (p_tenant_id, p_item_id, 'in', p_quantity, p_quantity, p_unit_cost,
            p_reference_type, p_reference_id, p_note, p_created_by);

    UPDATE items
       SET current_stock = current_stock + p_quantity, updated_at = now()
     WHERE item_id = p_item_id AND tenant_id = p_tenant_id;
END;
$$;
