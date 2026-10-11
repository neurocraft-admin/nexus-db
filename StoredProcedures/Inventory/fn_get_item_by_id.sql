-- One item, active or not (an inactive item is still readable so its ledger and edit form work).
CREATE OR REPLACE FUNCTION fn_get_item_by_id(p_tenant_id integer, p_item_id bigint)
RETURNS TABLE (item_id bigint, item_code varchar, item_name varchar, unit varchar, cost_price numeric,
               selling_price numeric, reorder_level numeric, current_stock numeric, is_active boolean,
               is_low_stock boolean)
LANGUAGE sql STABLE AS $$
    SELECT i.item_id, i.item_code, i.item_name, i.unit, i.cost_price, i.selling_price,
           i.reorder_level, i.current_stock, i.is_active,
           (i.is_active AND i.reorder_level > 0 AND i.current_stock <= i.reorder_level)
      FROM items i
     WHERE i.tenant_id = p_tenant_id
       AND i.item_id = p_item_id;
$$;
