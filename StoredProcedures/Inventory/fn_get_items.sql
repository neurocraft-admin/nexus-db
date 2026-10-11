-- Item list with stock. p_search matches the code or the name (case-insensitive, plain text: no wildcards);
-- p_active_only hides deactivated items. is_low_stock is true for an active item with a reorder level above
-- zero whose stock is at or below it (a reorder level of 0 means "no alert").
CREATE OR REPLACE FUNCTION fn_get_items(p_tenant_id integer, p_search varchar, p_active_only boolean)
RETURNS TABLE (item_id bigint, item_code varchar, item_name varchar, unit varchar, cost_price numeric,
               selling_price numeric, reorder_level numeric, current_stock numeric, is_active boolean,
               is_low_stock boolean)
LANGUAGE sql STABLE AS $$
    SELECT i.item_id, i.item_code, i.item_name, i.unit, i.cost_price, i.selling_price,
           i.reorder_level, i.current_stock, i.is_active,
           (i.is_active AND i.reorder_level > 0 AND i.current_stock <= i.reorder_level)
      FROM items i
     WHERE i.tenant_id = p_tenant_id
       AND (NOT COALESCE(p_active_only, false) OR i.is_active)
       AND (COALESCE(btrim(p_search), '') = ''
            OR position(lower(btrim(p_search)) IN lower(i.item_code || ' ' || i.item_name)) > 0)
     ORDER BY i.item_name, i.item_id;
$$;
