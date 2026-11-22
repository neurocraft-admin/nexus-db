-- The chosen lines of a template as the JSON array that sp_save_quotation reads (line type, item or package, description, unit, quantity, the
-- template's own price, make text and extra-charge flag), in the template's order. The make text key is always present, so a line whose make text is
-- blank stays blank on the quotation instead of falling back to the item's default.
CREATE OR REPLACE FUNCTION fn_template_lines_json(p_tenant_id integer, p_template_id bigint, p_include_line_ids bigint[])
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT jsonb_agg(jsonb_build_object('lineType', l.line_type, 'itemId', l.item_id, 'packageId', l.package_id,
                                        'description', l.description, 'unit', l.unit, 'quantity', l.quantity,
                                        'unitPrice', l.unit_price, 'makeText', l.make_text, 'isExtraCharge', l.is_extra_charge)
                     ORDER BY l.sort_order)
      FROM quotation_template_lines l
     WHERE l.tenant_id = p_tenant_id AND l.template_id = p_template_id AND l.template_line_id = ANY (p_include_line_ids);
$$;
