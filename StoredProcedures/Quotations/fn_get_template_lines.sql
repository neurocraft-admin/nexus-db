-- The lines of one template in their saved order, with the item or package code, the make text and extra-charge flag, and the item's or package's
-- CURRENT price beside the template's own (price_differs) and whether the item or package is still active (ref_is_active).
DROP FUNCTION IF EXISTS fn_get_template_lines(integer, bigint);
CREATE OR REPLACE FUNCTION fn_get_template_lines(p_tenant_id integer, p_template_id bigint)
RETURNS TABLE (template_line_id bigint, line_type varchar, item_id bigint, item_code varchar, package_id bigint,
               package_code varchar, description varchar, unit varchar, quantity numeric, unit_price numeric,
               sort_order integer, current_unit_price numeric, price_differs boolean, ref_is_active boolean,
               make_text varchar, is_extra_charge boolean)
LANGUAGE sql STABLE AS $$
    SELECT l.template_line_id, l.line_type, l.item_id, i.item_code, l.package_id, p.package_code, l.description,
           l.unit, l.quantity, l.unit_price, l.sort_order,
           COALESCE(i.selling_price, p.package_price),
           COALESCE(i.selling_price, p.package_price) IS NOT NULL
               AND COALESCE(i.selling_price, p.package_price) <> l.unit_price,
           COALESCE(i.is_active, p.is_active, true), l.make_text, l.is_extra_charge
      FROM quotation_template_lines l
      LEFT JOIN items i ON i.item_id = l.item_id
      LEFT JOIN packages p ON p.package_id = l.package_id
     WHERE l.tenant_id = p_tenant_id AND l.template_id = p_template_id
     ORDER BY l.sort_order, l.template_line_id;
$$;
