-- Insert (p_item_id NULL) or update an item master row. Returns the id. Stock is never set here: it changes only
-- through stock_in / stock_out / adjust, each with a ledger row.
--   23505 unique_violation  - the item code already exists (uq_items_tenant_code)
--   23503 foreign key       - the unit is not an active unit; the API maps it to 400
--   23514 check violation   - code not upper case letters/digits/. _ / -, or a negative price or level
--   P0002 not found         - unknown item on update
--   NX409 rule conflict     - an update changes the unit of an item that has stock movements or package lines
--                             (fn_check_item_unit_change; COLUMN names the unit)
CREATE OR REPLACE FUNCTION fn_save_item(
    p_tenant_id integer, p_item_id bigint, p_item_code varchar, p_item_name varchar, p_unit varchar,
    p_cost_price numeric, p_selling_price numeric, p_reorder_level numeric)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_item_id bigint;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM units u
                    WHERE u.tenant_id = p_tenant_id AND u.unit_code = p_unit AND u.is_active) THEN
        RAISE EXCEPTION 'Unit % is not available', p_unit USING ERRCODE = '23503';
    END IF;

    IF p_item_id IS NOT NULL THEN
        PERFORM fn_check_item_unit_change(p_tenant_id, p_item_id, p_unit);
    END IF;

    IF p_item_id IS NULL THEN
        INSERT INTO items (tenant_id, item_code, item_name, unit, cost_price, selling_price, reorder_level)
        VALUES (p_tenant_id, p_item_code, p_item_name, p_unit, p_cost_price, p_selling_price, p_reorder_level)
        RETURNING items.item_id INTO v_item_id;
    ELSE
        UPDATE items
           SET item_code = p_item_code, item_name = p_item_name, unit = p_unit, cost_price = p_cost_price,
               selling_price = p_selling_price, reorder_level = p_reorder_level, updated_at = now()
         WHERE items.item_id = p_item_id AND items.tenant_id = p_tenant_id
        RETURNING items.item_id INTO v_item_id;

        IF v_item_id IS NULL THEN
            RAISE EXCEPTION 'Item % not found', p_item_id USING ERRCODE = 'P0002';
        END IF;
    END IF;
    RETURN v_item_id;
END;
$$;
