-- The stock an order needs, one row per stock-out: an item line gives its item and quantity; a package line gives
-- every component of the package (fn_get_package_components, for ONE set) multiplied by the line's quantity. A
-- custom line needs no stock and gives no row. Rows come in line order, then component order, which is the order
-- sp_take_order_stock takes the stock in. The same item can appear on several rows; callers that compare with
-- stock add them up per item.
CREATE OR REPLACE FUNCTION fn_get_order_requirements(p_tenant_id integer, p_order_id bigint)
RETURNS TABLE (order_line_id bigint, line_sort integer, component_sort integer, item_id bigint, quantity numeric)
LANGUAGE sql STABLE AS $$
    SELECT ol.order_line_id, ol.sort_order, 0, ol.item_id, ol.quantity
      FROM order_lines ol
     WHERE ol.tenant_id = p_tenant_id AND ol.order_id = p_order_id AND ol.line_type = 'item'
    UNION ALL
    SELECT ol.order_line_id, ol.sort_order, c.sort_order, c.item_id, c.quantity * ol.quantity
      FROM order_lines ol
     CROSS JOIN LATERAL fn_get_package_components(ol.tenant_id, ol.package_id) c
     WHERE ol.tenant_id = p_tenant_id AND ol.order_id = p_order_id AND ol.line_type = 'package'
     ORDER BY 2, 3;
$$;
