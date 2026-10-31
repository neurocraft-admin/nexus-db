-- Checks that every item and package named by the lines exists in this tenant and is active. Used by quotations
-- and templates, so a document never carries a line that cannot be sold.
--   P0002 not found     - an item or package that does not exist (the message lists the ids)
--   NX409 rule conflict - an inactive item or package (the message lists the codes): remove or replace it
CREATE OR REPLACE PROCEDURE sp_check_document_references(p_tenant_id integer, p_lines jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    v_list text;
BEGIN
    SELECT string_agg(x.id::text, ', ' ORDER BY x.id) INTO v_list
      FROM (SELECT DISTINCT l."itemId" AS id FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint)
             WHERE l."itemId" IS NOT NULL) x
     WHERE NOT EXISTS (SELECT 1 FROM items i WHERE i.item_id = x.id AND i.tenant_id = p_tenant_id);
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'Items not found: %', v_list USING ERRCODE = 'P0002', COLUMN = 'lines';
    END IF;
    SELECT string_agg(x.id::text, ', ' ORDER BY x.id) INTO v_list
      FROM (SELECT DISTINCT l."packageId" AS id FROM jsonb_to_recordset(p_lines) AS l ("packageId" bigint)
             WHERE l."packageId" IS NOT NULL) x
     WHERE NOT EXISTS (SELECT 1 FROM packages p WHERE p.package_id = x.id AND p.tenant_id = p_tenant_id);
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'Packages not found: %', v_list USING ERRCODE = 'P0002', COLUMN = 'lines';
    END IF;
    SELECT string_agg(i.item_code, ', ' ORDER BY i.item_id) INTO v_list
      FROM items i WHERE i.tenant_id = p_tenant_id AND NOT i.is_active
       AND i.item_id IN (SELECT l."itemId" FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint));
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'Inactive items: %. Remove or replace them', v_list USING ERRCODE = 'NX409', COLUMN = 'lines';
    END IF;
    SELECT string_agg(p.package_code, ', ' ORDER BY p.package_id) INTO v_list
      FROM packages p WHERE p.tenant_id = p_tenant_id AND NOT p.is_active
       AND p.package_id IN (SELECT l."packageId" FROM jsonb_to_recordset(p_lines) AS l ("packageId" bigint));
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'Inactive packages: %. Remove or replace them', v_list USING ERRCODE = 'NX409', COLUMN = 'lines';
    END IF;
END;
$$;
