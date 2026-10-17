-- Refuses to change an item's unit once the item has stock movements or is a line in a package: the quantities
-- already recorded (and the quantity in each package line) are in the old unit, so a change would silently change
-- what they mean. Called by fn_save_item on an update. The item row is locked FOR UPDATE, like every stock
-- movement does, so a movement cannot slip in between this check and the update.
--   NX409 rule conflict - the unit differs and the item has movements or package lines; COLUMN names the unit
-- An unknown item returns quietly: fn_save_item's UPDATE reports it (P0002). The same unit is always allowed.
CREATE OR REPLACE FUNCTION fn_check_item_unit_change(p_tenant_id integer, p_item_id bigint, p_unit varchar)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_unit varchar;
BEGIN
    SELECT i.unit INTO v_unit FROM items i
     WHERE i.item_id = p_item_id AND i.tenant_id = p_tenant_id
       FOR UPDATE;
    IF NOT FOUND OR v_unit = p_unit THEN
        RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM stock_movements m WHERE m.item_id = p_item_id AND m.tenant_id = p_tenant_id)
       OR EXISTS (SELECT 1 FROM package_lines pl WHERE pl.item_id = p_item_id AND pl.tenant_id = p_tenant_id) THEN
        RAISE EXCEPTION 'The unit cannot be changed because this item has stock movements or is in a package'
            USING ERRCODE = 'NX409', COLUMN = 'unit';
    END IF;
END;
$$;
