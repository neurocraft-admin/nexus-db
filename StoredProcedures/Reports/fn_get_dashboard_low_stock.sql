-- The items most short of their minimum (active, with a reorder level, stock at or below it), most short first, with how many there are in all
-- (total_count on every row) so the card can say "1 more item is below minimum". is_below_half: stock under half the minimum.
CREATE OR REPLACE FUNCTION fn_get_dashboard_low_stock(p_tenant_id integer, p_limit integer)
RETURNS TABLE (item_id bigint, item_code varchar, item_name varchar, unit varchar, reorder_level numeric, current_stock numeric,
               is_below_half boolean, total_count bigint)
LANGUAGE sql STABLE AS $$
    SELECT i.item_id, i.item_code, i.item_name, i.unit, i.reorder_level, i.current_stock, i.is_below_half, count(*) OVER ()
      FROM vw_inventory_status i
     WHERE i.tenant_id = p_tenant_id AND i.is_low
     ORDER BY i.stock_over_minimum, i.item_name, i.item_id
     LIMIT p_limit;
$$;
