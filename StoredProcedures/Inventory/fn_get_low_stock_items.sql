-- Active items with a reorder level above zero whose stock is at or below it, most short first.
CREATE OR REPLACE FUNCTION fn_get_low_stock_items(p_tenant_id integer)
RETURNS TABLE (item_id bigint, item_code varchar, item_name varchar, unit varchar,
               reorder_level numeric, current_stock numeric)
LANGUAGE sql STABLE AS $$
    SELECT i.item_id, i.item_code, i.item_name, i.unit, i.reorder_level, i.current_stock
      FROM items i
     WHERE i.tenant_id = p_tenant_id
       AND i.is_active
       AND i.reorder_level > 0
       AND i.current_stock <= i.reorder_level
     ORDER BY (i.current_stock - i.reorder_level), i.item_name, i.item_id;
$$;
