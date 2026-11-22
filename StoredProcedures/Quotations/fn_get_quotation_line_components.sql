-- The component items of the PACKAGE lines of a quotation, as copied from the package when the quotation was saved, in the order of their line and
-- then of the package. quantity is per ONE set; quantity_total is that times the line's quantity (what the proposal prints). make_text is the make
-- text this quotation will print for the component (the item's default unless it was overridden on the quotation).
CREATE OR REPLACE FUNCTION fn_get_quotation_line_components(p_tenant_id integer, p_quotation_id bigint)
RETURNS TABLE (quotation_line_id bigint, line_sort_order integer, item_id bigint, item_code varchar, description varchar, unit varchar,
               quantity numeric, quantity_total numeric, make_text varchar, sort_order integer)
LANGUAGE sql STABLE AS $$
    SELECT c.quotation_line_id, l.sort_order, c.item_id, i.item_code, c.description, c.unit, c.quantity, round(c.quantity * l.quantity, 3), c.make_text, c.sort_order
      FROM quotation_line_components c
      JOIN quotation_lines l ON l.quotation_line_id = c.quotation_line_id
      JOIN items i ON i.item_id = c.item_id
     WHERE c.tenant_id = p_tenant_id AND l.quotation_id = p_quotation_id
     ORDER BY l.sort_order, c.sort_order, c.component_id;
$$;
