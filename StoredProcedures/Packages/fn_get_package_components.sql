-- Items and quantities (for ONE set) of a package, in saved order. Order fulfilment (the Quotation module) takes
-- stock out with these, multiplied by the order line's quantity. An inactive component is still returned: the
-- stock-out then fails with a conflict naming that item, which is what should happen.
CREATE OR REPLACE FUNCTION fn_get_package_components(p_tenant_id integer, p_package_id bigint)
RETURNS TABLE (item_id bigint, item_code varchar, item_name varchar, unit varchar, quantity numeric,
               is_active boolean, sort_order integer)
LANGUAGE sql STABLE AS $$
    SELECT pl.item_id, i.item_code, i.item_name, i.unit, pl.quantity, i.is_active, pl.sort_order
      FROM package_lines pl
      JOIN items i ON i.item_id = pl.item_id
     WHERE pl.tenant_id = p_tenant_id
       AND pl.package_id = p_package_id
     ORDER BY pl.sort_order, pl.package_line_id;
$$;
