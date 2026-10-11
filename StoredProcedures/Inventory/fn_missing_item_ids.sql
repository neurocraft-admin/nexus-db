-- The item ids in a purchase's JSON lines that do not exist for the tenant, as "1, 2" (NULL when none), so the
-- "items not found" message can say which ones. Used by sp_check_purchase_lines.
CREATE OR REPLACE FUNCTION fn_missing_item_ids(p_tenant_id integer, p_lines jsonb)
RETURNS varchar
LANGUAGE sql STABLE AS $$
    SELECT string_agg(l."itemId"::text, ', ' ORDER BY l."itemId")
      FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint)
     WHERE NOT EXISTS (SELECT 1 FROM items i WHERE i.tenant_id = p_tenant_id AND i.item_id = l."itemId");
$$;
