-- Copies the lines, the package component rows (with their overrides) and the datasheet list of one quotation onto another. Used by
-- sp_duplicate_quotation inside its transaction. Component rows follow their line by the line's position (sort_order).
CREATE OR REPLACE PROCEDURE sp_copy_quotation_children(p_tenant_id integer, p_from_id bigint, p_to_id bigint)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO quotation_lines (tenant_id, quotation_id, line_type, item_id, package_id, description, unit,
                                 quantity, unit_price, line_total, sort_order, make_text, is_extra_charge)
    SELECT l.tenant_id, p_to_id, l.line_type, l.item_id, l.package_id, l.description, l.unit,
           l.quantity, l.unit_price, l.line_total, l.sort_order, l.make_text, l.is_extra_charge
      FROM quotation_lines l WHERE l.quotation_id = p_from_id AND l.tenant_id = p_tenant_id;
    INSERT INTO quotation_line_components (tenant_id, quotation_line_id, item_id, description, unit, quantity, make_text, sort_order)
    SELECT c.tenant_id, nl.quotation_line_id, c.item_id, c.description, c.unit, c.quantity, c.make_text, c.sort_order
      FROM quotation_lines ol
      JOIN quotation_line_components c ON c.quotation_line_id = ol.quotation_line_id
      JOIN quotation_lines nl ON nl.quotation_id = p_to_id AND nl.sort_order = ol.sort_order
     WHERE ol.quotation_id = p_from_id AND ol.tenant_id = p_tenant_id;
    INSERT INTO quotation_datasheets (tenant_id, quotation_id, datasheet_id, sort_order)
    SELECT d.tenant_id, p_to_id, d.datasheet_id, d.sort_order FROM quotation_datasheets d
     WHERE d.quotation_id = p_from_id AND d.tenant_id = p_tenant_id;
END;
$$;
