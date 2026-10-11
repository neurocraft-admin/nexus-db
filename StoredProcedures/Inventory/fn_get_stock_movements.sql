-- The stock ledger, newest first, for one item or all items, with a date range and paging. Each row also
-- carries total_count (rows matching the filter, before paging) so the caller can show "page x of y".
-- p_from / p_to are calendar dates in the business time zone (app_settings business_time_zone, default UTC),
-- inclusive; NULL means no limit. p_limit NULL returns everything (the API caps what it asks for).
CREATE OR REPLACE FUNCTION fn_get_stock_movements(
    p_tenant_id integer, p_item_id bigint, p_from date, p_to date, p_limit integer, p_offset integer)
RETURNS TABLE (movement_id bigint, item_id bigint, item_code varchar, item_name varchar, unit varchar,
               movement_type varchar, quantity numeric, signed_quantity numeric, unit_cost numeric,
               reference_type varchar, reference_id bigint, note varchar, created_by integer,
               created_at timestamptz, total_count bigint)
LANGUAGE sql STABLE AS $$
    WITH tz AS (
        SELECT COALESCE(fn_get_setting(p_tenant_id, 'business_time_zone'), 'UTC') AS name
    )
    SELECT m.movement_id, m.item_id, i.item_code, i.item_name, i.unit, m.movement_type, m.quantity,
           m.signed_quantity, m.unit_cost, m.reference_type, m.reference_id, m.note, m.created_by,
           m.created_at, count(*) OVER ()
      FROM stock_movements m
      JOIN items i ON i.item_id = m.item_id
      CROSS JOIN tz
     WHERE m.tenant_id = p_tenant_id
       AND (p_item_id IS NULL OR m.item_id = p_item_id)
       AND (p_from IS NULL OR m.created_at >= (p_from::timestamp AT TIME ZONE tz.name))
       AND (p_to IS NULL OR m.created_at < ((p_to + 1)::timestamp AT TIME ZONE tz.name))
     ORDER BY m.created_at DESC, m.movement_id DESC
     LIMIT p_limit OFFSET COALESCE(p_offset, 0);
$$;
