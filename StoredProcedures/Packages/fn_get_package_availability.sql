-- Can we supply p_quantity sets? Per component: required (quantity x sets), available (current stock) and
-- short_by. sets_possible is how many complete sets the stock allows (the same on every row). This only READS
-- stock: it never reserves or deducts, and the caller never blocks on it. Two packages that share a component
-- are not combined here; the Quotation module sums across its lines.
--   22023 invalid parameter - p_quantity is not a whole number from 1 to 1000 (COLUMN names the field)
--   P0002 not found         - unknown package
CREATE OR REPLACE FUNCTION fn_get_package_availability(p_tenant_id integer, p_package_id bigint, p_quantity integer)
RETURNS TABLE (item_id bigint, item_code varchar, item_name varchar, unit varchar, quantity_per_set numeric,
               required numeric, available numeric, short_by numeric, is_active boolean, sets_possible bigint)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    c_max_sets CONSTANT integer := 1000;
BEGIN
    IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > c_max_sets THEN
        RAISE EXCEPTION 'The number of sets must be a whole number from 1 to %', c_max_sets
            USING ERRCODE = '22023', COLUMN = 'quantity';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM packages p WHERE p.package_id = p_package_id AND p.tenant_id = p_tenant_id) THEN
        RAISE EXCEPTION 'Package % not found', p_package_id USING ERRCODE = 'P0002';
    END IF;
    RETURN QUERY
    SELECT pl.item_id, i.item_code, i.item_name, i.unit, pl.quantity, pl.quantity * p_quantity,
           i.current_stock, greatest(pl.quantity * p_quantity - i.current_stock, 0), i.is_active,
           (min(floor(i.current_stock / pl.quantity)) OVER ())::bigint
      FROM package_lines pl
      JOIN items i ON i.item_id = pl.item_id
     WHERE pl.tenant_id = p_tenant_id AND pl.package_id = p_package_id
     ORDER BY pl.sort_order, pl.package_line_id;
END;
$$;
