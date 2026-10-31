-- The lines of a template in saved order. current_unit_price is what the item (selling price) or package (typed
-- price) costs TODAY, and price_differs says the template's own copied price is not that, so the screen can show
-- "differs from the current price". Custom lines have no current price. ref_is_active is false when the item or
-- package has been deactivated since (the line cannot be put on a quotation until it is replaced).
CREATE OR REPLACE FUNCTION fn_get_template_lines(p_tenant_id integer, p_template_id bigint)
RETURNS TABLE (template_line_id bigint, line_type varchar, item_id bigint, item_code varchar, package_id bigint,
               package_code varchar, description varchar, unit varchar, quantity numeric, unit_price numeric,
               sort_order integer, current_unit_price numeric, price_differs boolean, ref_is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT l.template_line_id, l.line_type, l.item_id, i.item_code, l.package_id, p.package_code, l.description,
           l.unit, l.quantity, l.unit_price, l.sort_order,
           COALESCE(i.selling_price, p.package_price),
           COALESCE(i.selling_price, p.package_price) IS NOT NULL
               AND COALESCE(i.selling_price, p.package_price) <> l.unit_price,
           COALESCE(i.is_active, p.is_active, true)
      FROM quotation_template_lines l
      LEFT JOIN items i ON i.item_id = l.item_id
      LEFT JOIN packages p ON p.package_id = l.package_id
     WHERE l.tenant_id = p_tenant_id AND l.template_id = p_template_id
     ORDER BY l.sort_order, l.template_line_id;
$$;
