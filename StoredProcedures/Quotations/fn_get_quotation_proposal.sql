-- The rows of the technical proposal of a quotation, in print order. One row per line, and under a PACKAGE line one row per component item:
--   row_kind 'line'      an item or custom line: description, unit, quantity, make_text, and its price (unit_price, line_total)
--   row_kind 'package'   a package line, with its own price; the proposal prints the package's components instead and never the package price
--   row_kind 'component' a component of the package row above it: quantity is the package's quantity times the component's, no price
-- is_extra_charge marks a pass-through line (the KSEB charges): printed in the table and in its Total, but outside the customer payable.
-- The Total row of the proposal is the quotation's total_amount. Whether prices are shown at all is quotations.show_line_prices.
CREATE OR REPLACE FUNCTION fn_get_quotation_proposal(p_tenant_id integer, p_quotation_id bigint)
RETURNS TABLE (line_sort_order integer, row_kind varchar, description varchar, unit varchar, quantity numeric, make_text varchar,
               is_extra_charge boolean, unit_price numeric, line_total numeric)
LANGUAGE sql STABLE AS $$
    SELECT r.line_sort_order, r.row_kind, r.description, r.unit, r.quantity, r.make_text, r.is_extra_charge, r.unit_price, r.line_total
      FROM (SELECT l.sort_order AS line_sort_order, 0 AS part, 0 AS sub, CASE l.line_type WHEN 'package' THEN 'package' ELSE 'line' END::varchar AS row_kind,
                   l.description, l.unit, l.quantity, l.make_text, l.is_extra_charge, l.unit_price, l.line_total
              FROM quotation_lines l
             WHERE l.tenant_id = p_tenant_id AND l.quotation_id = p_quotation_id
            UNION ALL
            SELECT l.sort_order, 1, c.sort_order, 'component'::varchar, c.description, c.unit, round(c.quantity * l.quantity, 3), c.make_text, false,
                   NULL::numeric, NULL::numeric
              FROM quotation_line_components c
              JOIN quotation_lines l ON l.quotation_line_id = c.quotation_line_id
             WHERE c.tenant_id = p_tenant_id AND l.quotation_id = p_quotation_id) r
     ORDER BY r.line_sort_order, r.part, r.sub;
$$;
