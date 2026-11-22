-- Copies the component items of every PACKAGE line of a saved quotation onto the quotation (quotation_line_components), so the technical proposal can
-- print them as separate rows and the quotation no longer changes when the package is edited later. The quantity is per ONE set (the proposal
-- multiplies by the line's quantity). The make text of a component is, in this order: the one given for it in the line's "components" (blank means
-- none), else the item's default make text. Called by sp_write_quotation after the lines are written, inside its transaction.
-- p_lines is the same JSON that was saved (line n of the array is the line with sort_order n).
CREATE OR REPLACE PROCEDURE sp_write_line_components(p_tenant_id integer, p_quotation_id bigint, p_lines jsonb)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO quotation_line_components (tenant_id, quotation_line_id, item_id, description, unit, quantity, make_text, sort_order)
    SELECT p_tenant_id, ql.quotation_line_id, pl.item_id, i.item_name, i.unit, pl.quantity,
           CASE WHEN o.has_override THEN NULLIF(btrim(o.make_text), '') ELSE i.make_text END, pl.sort_order
      FROM quotation_lines ql
      JOIN package_lines pl ON pl.package_id = ql.package_id AND pl.tenant_id = ql.tenant_id
      JOIN items i ON i.item_id = pl.item_id
      LEFT JOIN LATERAL (
            SELECT (c.comp ? 'makeText') AS has_override, (c.comp ->> 'makeText') AS make_text
              FROM jsonb_array_elements(COALESCE((SELECT CASE WHEN jsonb_typeof(e.line -> 'components') = 'array' THEN e.line -> 'components' END
                                                    FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS e (line, ord)
                                                   WHERE e.ord = ql.sort_order), '[]'::jsonb)) AS c (comp)
             WHERE (c.comp ->> 'itemId')::bigint = pl.item_id
             LIMIT 1) o ON true
     WHERE ql.tenant_id = p_tenant_id AND ql.quotation_id = p_quotation_id AND ql.line_type = 'package';
END;
$$;
