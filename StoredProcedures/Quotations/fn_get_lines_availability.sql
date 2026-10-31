-- "Short by N" for a set of quotation lines, WITHOUT saving anything: the stock the lines would need, added up per
-- item across every item line and every package component (quantity x the line's quantity), against each item's
-- current stock. This is a warning only: a quotation is never blocked and never deducts stock. p_lines uses the
-- same JSON as sp_check_document_lines (only lineType, itemId, packageId and quantity are read); custom lines and
-- lines that name nothing in this tenant are ignored. Two packages that share a component are therefore combined,
-- which is what fn_get_package_availability leaves to the quotation.
CREATE OR REPLACE FUNCTION fn_get_lines_availability(p_tenant_id integer, p_lines jsonb)
RETURNS TABLE (item_id bigint, item_code varchar, item_name varchar, unit varchar, required numeric,
               available numeric, short_by numeric, is_active boolean)
LANGUAGE sql STABLE AS $$
    WITH lines AS (
        SELECT l."lineType", l."itemId", l."packageId", l.quantity
          FROM jsonb_to_recordset(p_lines) AS l ("lineType" text, "itemId" bigint, "packageId" bigint, quantity numeric)
         WHERE l.quantity > 0),
    need AS (
        SELECT l."itemId" AS item_id, l.quantity AS qty FROM lines l WHERE l."lineType" = 'item'
        UNION ALL
        SELECT pl.item_id, pl.quantity * l.quantity FROM lines l
          JOIN package_lines pl ON pl.package_id = l."packageId" AND pl.tenant_id = p_tenant_id
         WHERE l."lineType" = 'package')
    SELECT i.item_id, i.item_code, i.item_name, i.unit, sum(n.qty), i.current_stock,
           greatest(sum(n.qty) - i.current_stock, 0), i.is_active
      FROM need n
      JOIN items i ON i.item_id = n.item_id AND i.tenant_id = p_tenant_id
     GROUP BY i.item_id, i.item_code, i.item_name, i.unit, i.current_stock, i.is_active
     ORDER BY i.item_code;
$$;
