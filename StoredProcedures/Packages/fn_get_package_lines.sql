-- The components of one package in the order they were saved, with the item's live name, unit, cost, selling
-- price, stock and active flag. line_cost / line_selling are round(quantity x price, 2); short_by is how much
-- stock is missing for ONE set (0 when there is enough).
CREATE OR REPLACE FUNCTION fn_get_package_lines(p_tenant_id integer, p_package_id bigint)
RETURNS TABLE (package_line_id bigint, item_id bigint, item_code varchar, item_name varchar, unit varchar,
               quantity numeric, unit_cost numeric, line_cost numeric, selling_price numeric,
               line_selling numeric, current_stock numeric, is_active boolean, short_by numeric, sort_order integer)
LANGUAGE sql STABLE AS $$
    SELECT pl.package_line_id, pl.item_id, i.item_code, i.item_name, i.unit, pl.quantity, i.cost_price,
           round(pl.quantity * i.cost_price, 2), i.selling_price, round(pl.quantity * i.selling_price, 2),
           i.current_stock, i.is_active, greatest(pl.quantity - i.current_stock, 0), pl.sort_order
      FROM package_lines pl
      JOIN items i ON i.item_id = pl.item_id
     WHERE pl.tenant_id = p_tenant_id
       AND pl.package_id = p_package_id
     ORDER BY pl.sort_order, pl.package_line_id;
$$;
