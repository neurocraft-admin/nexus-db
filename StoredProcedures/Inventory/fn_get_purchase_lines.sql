-- The lines of one purchase, in the order they were stored (by item id).
CREATE OR REPLACE FUNCTION fn_get_purchase_lines(p_tenant_id integer, p_purchase_id bigint)
RETURNS TABLE (purchase_line_id bigint, item_id bigint, item_code varchar, item_name varchar, unit varchar,
               quantity numeric, unit_cost numeric, line_total numeric)
LANGUAGE sql STABLE AS $$
    SELECT pl.purchase_line_id, pl.item_id, i.item_code, i.item_name, i.unit,
           pl.quantity, pl.unit_cost, pl.line_total
      FROM purchase_lines pl
      JOIN items i ON i.item_id = pl.item_id
     WHERE pl.tenant_id = p_tenant_id
       AND pl.purchase_id = p_purchase_id
     ORDER BY pl.purchase_line_id;
$$;
