-- Deactivate or reactivate an item. Allowed while stock remains (the ledger keeps it); an inactive item is
-- refused by purchases and stock-out but can still be adjusted so it can be brought to zero.
--   P0002 not found
CREATE OR REPLACE FUNCTION fn_set_item_active(p_tenant_id integer, p_item_id bigint, p_is_active boolean)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE items
       SET is_active = p_is_active, updated_at = now()
     WHERE item_id = p_item_id AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item % not found', p_item_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;
