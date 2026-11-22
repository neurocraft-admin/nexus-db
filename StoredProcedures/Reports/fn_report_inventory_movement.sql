-- Report: stock movement per item over a range of business days (both missing = the current month; at most 366 days). One row per item that
-- had stock before the range or a movement in it (p_item_id limits it to one item):
--   opening  stock at the start of the first day (every movement before it)
--   stock_in / stock_out  the quantity received and the quantity sent out (both positive)
--   adjustments  the NET of stock corrections in the range (signed: a count that found more is positive)
--   closing = opening + stock_in - stock_out + adjustments, and when the range ends today it equals current_stock.
-- Quantities only: items have different units, so there is no total row and no value (a purchase's cost is not a stock valuation).
--   22023 invalid parameter - a bad range (COLUMN from or to)
CREATE OR REPLACE FUNCTION fn_report_inventory_movement(p_tenant_id integer, p_from date, p_to date, p_item_id bigint DEFAULT NULL)
RETURNS TABLE (item_id bigint, item_code varchar, item_name varchar, unit varchar, opening numeric, stock_in numeric, stock_out numeric,
               adjustments numeric, closing numeric, current_stock numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_from date;
    v_to   date;
BEGIN
    SELECT r.range_from, r.range_to INTO v_from, v_to FROM fn_resolve_report_range(p_tenant_id, p_from, p_to) r;
    RETURN QUERY
    SELECT m.item_id, m.item_code, m.item_name, m.unit, m.opening, m.stock_in, m.stock_out, m.adjustments,
           m.opening + m.stock_in - m.stock_out + m.adjustments, i.current_stock
      FROM (SELECT l.item_id, l.item_code, l.item_name, l.unit,
                   COALESCE(sum(l.signed_quantity) FILTER (WHERE l.created_date < v_from), 0) AS opening,
                   COALESCE(sum(l.quantity) FILTER (WHERE l.created_date BETWEEN v_from AND v_to AND l.movement_type = 'in'), 0) AS stock_in,
                   COALESCE(sum(l.quantity) FILTER (WHERE l.created_date BETWEEN v_from AND v_to AND l.movement_type = 'out'), 0) AS stock_out,
                   COALESCE(sum(l.signed_quantity) FILTER (WHERE l.created_date BETWEEN v_from AND v_to AND l.movement_type = 'adjust'), 0) AS adjustments
              FROM vw_stock_ledger l
             WHERE l.tenant_id = p_tenant_id AND l.created_date <= v_to AND (p_item_id IS NULL OR l.item_id = p_item_id)
             GROUP BY l.item_id, l.item_code, l.item_name, l.unit) m
      JOIN items i ON i.item_id = m.item_id
     WHERE m.opening <> 0 OR m.stock_in <> 0 OR m.stock_out <> 0 OR m.adjustments <> 0
     ORDER BY m.item_name, m.item_id;
END;
$$;
