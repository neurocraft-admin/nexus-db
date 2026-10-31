-- The lines of an order in saved order, as quoted. Custom lines are listed but need no stock.
CREATE OR REPLACE FUNCTION fn_get_order_lines(p_tenant_id integer, p_order_id bigint)
RETURNS TABLE (order_line_id bigint, line_type varchar, item_id bigint, item_code varchar, package_id bigint,
               package_code varchar, description varchar, unit varchar, quantity numeric, unit_price numeric,
               line_total numeric, sort_order integer)
LANGUAGE sql STABLE AS $$
    SELECT l.order_line_id, l.line_type, l.item_id, i.item_code, l.package_id, p.package_code, l.description,
           l.unit, l.quantity, l.unit_price, l.line_total, l.sort_order
      FROM order_lines l
      LEFT JOIN items i ON i.item_id = l.item_id
      LEFT JOIN packages p ON p.package_id = l.package_id
     WHERE l.tenant_id = p_tenant_id AND l.order_id = p_order_id
     ORDER BY l.sort_order, l.order_line_id;
$$;
