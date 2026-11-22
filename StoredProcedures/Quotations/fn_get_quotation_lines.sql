-- The lines of one quotation in their saved order, with the item or package code and the make text and extra-charge flag of the new format.
-- (The component items of a package line are fn_get_quotation_line_components.)
DROP FUNCTION IF EXISTS fn_get_quotation_lines(integer, bigint);
CREATE OR REPLACE FUNCTION fn_get_quotation_lines(p_tenant_id integer, p_quotation_id bigint)
RETURNS TABLE (quotation_line_id bigint, line_type varchar, item_id bigint, item_code varchar, package_id bigint,
               package_code varchar, description varchar, unit varchar, quantity numeric, unit_price numeric,
               line_total numeric, sort_order integer, make_text varchar, is_extra_charge boolean)
LANGUAGE sql STABLE AS $$
    SELECT l.quotation_line_id, l.line_type, l.item_id, i.item_code, l.package_id, p.package_code, l.description,
           l.unit, l.quantity, l.unit_price, l.line_total, l.sort_order, l.make_text, l.is_extra_charge
      FROM quotation_lines l
      LEFT JOIN items i ON i.item_id = l.item_id
      LEFT JOIN packages p ON p.package_id = l.package_id
     WHERE l.tenant_id = p_tenant_id AND l.quotation_id = p_quotation_id
     ORDER BY l.sort_order, l.quotation_line_id;
$$;
