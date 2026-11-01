-- Every stock problem an order has right now, one row per item, so a screen can show the whole list at once:
--   problem 'inactive' - the item (or a package component) has been deactivated; replace it first
--   problem 'short'    - the total the order needs of this item (item lines and package components added up)
--                        is more than its current stock
-- requested and available are in the item's unit. No rows means the stock side of the order is fine. This only
-- READS; sp_fulfil_order checks the same thing under locks. The API calls it after a fulfilment was refused, so
-- the person gets structured rows and not text cut out of an error message.
CREATE OR REPLACE FUNCTION fn_get_order_shortages(p_tenant_id integer, p_order_id bigint)
RETURNS TABLE (item_id bigint, item_code varchar, item_name varchar, unit varchar, requested numeric,
               available numeric, problem varchar)
LANGUAGE sql STABLE AS $$
    SELECT x.item_id, x.item_code, x.item_name, x.unit, x.needed, x.current_stock,
           (CASE WHEN NOT x.is_active THEN 'inactive' ELSE 'short' END)::varchar
      FROM (SELECT i.item_id, i.item_code, i.item_name, i.unit, i.current_stock, i.is_active, sum(r.quantity) AS needed
              FROM fn_get_order_requirements(p_tenant_id, p_order_id) r
              JOIN items i ON i.item_id = r.item_id AND i.tenant_id = p_tenant_id
             GROUP BY i.item_id, i.item_code, i.item_name, i.unit, i.current_stock, i.is_active) x
     WHERE NOT x.is_active OR x.current_stock < x.needed
     ORDER BY x.item_code, x.item_id;
$$;
