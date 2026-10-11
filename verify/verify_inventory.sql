-- Module 5 (Inventory). Run after every release. Raises an exception naming the first thing that is missing.
DO $$
DECLARE
    v_name text;
    c_tables CONSTANT text[] := ARRAY['units', 'items', 'suppliers', 'purchases', 'purchase_lines', 'stock_movements'];
    c_functions CONSTANT text[] := ARRAY[
        'fn_get_units', 'fn_get_items', 'fn_get_item_by_id', 'fn_save_item', 'fn_set_item_active',
        'fn_get_low_stock_items', 'fn_get_suppliers', 'fn_get_supplier_by_id', 'fn_save_supplier',
        'fn_set_supplier_active', 'sp_stock_in', 'sp_stock_out', 'sp_adjust_stock', 'fn_check_purchase_header',
        'sp_check_purchase_lines', 'sp_add_purchase_lines', 'sp_record_purchase', 'fn_get_purchases', 'fn_get_purchase_by_id', 'fn_get_purchase_lines',
        'fn_get_stock_movements', 'fn_block_stock_movement_change'];
BEGIN
    FOREACH v_name IN ARRAY ARRAY['10_inventory_schema.sql', '11_inventory_menu.sql'] LOOP
        IF NOT EXISTS (SELECT 1 FROM deployment_log d WHERE d.script_name = v_name) THEN
            RAISE EXCEPTION 'Script not applied: %', v_name;
        END IF;
    END LOOP;

    FOREACH v_name IN ARRAY c_tables LOOP
        IF to_regclass('public.' || v_name) IS NULL THEN
            RAISE EXCEPTION 'Table missing: %', v_name;
        END IF;
    END LOOP;
    IF to_regclass('public.vw_item_stock_check') IS NULL THEN
        RAISE EXCEPTION 'View missing: vw_item_stock_check';
    END IF;

    FOREACH v_name IN ARRAY c_functions LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = v_name) THEN
            RAISE EXCEPTION 'Function missing: %', v_name;
        END IF;
    END LOOP;

    FOREACH v_name IN ARRAY ARRAY['trg_stock_movements_no_change', 'trg_stock_movements_no_truncate'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgname = v_name AND NOT t.tgisinternal) THEN
            RAISE EXCEPTION 'Trigger missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['ck_items_stock_not_negative', 'ck_stock_movements_quantity',
                                  'ck_stock_movements_direction', 'ck_stock_movements_adjust_note'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = v_name) THEN
            RAISE EXCEPTION 'Constraint missing: %', v_name;
        END IF;
    END LOOP;

    IF (SELECT count(*) FROM units WHERE unit_code IN ('nos', 'm', 'kg', 'ltr', 'pack')) < 5 THEN
        RAISE EXCEPTION 'Seed units missing (nos, m, kg, ltr, pack)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM app_settings WHERE setting_key = 'business_time_zone') THEN
        RAISE EXCEPTION 'Setting missing: business_time_zone';
    END IF;

    FOREACH v_name IN ARRAY ARRAY['items', 'purchases', 'stock'] LOOP
        IF NOT EXISTS (SELECT 1
                         FROM role_permissions rp
                         JOIN roles r ON r.role_id = rp.role_id
                         JOIN resources x ON x.resource_id = rp.resource_id
                        WHERE r.role_name = 'Admin' AND x.resource_code = v_name
                          AND rp.can_view AND rp.can_create AND rp.can_update AND rp.can_delete) THEN
            RAISE EXCEPTION 'Admin does not have full access to %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['/inventory/items', '/inventory/purchases', '/inventory/stock'] LOOP
        IF NOT EXISTS (SELECT 1 FROM menu_items WHERE url = v_name AND parent_id IS NOT NULL) THEN
            RAISE EXCEPTION 'Menu item missing: %', v_name;
        END IF;
    END LOOP;

    -- The ledger must always agree with the running stock.
    IF EXISTS (SELECT 1 FROM vw_item_stock_check WHERE difference <> 0) THEN
        RAISE EXCEPTION 'Stock does not reconcile with the ledger for at least one item (vw_item_stock_check)';
    END IF;

    -- The API connects as nexus_app: it must be able to use what was just created. (Ledger rows cannot be
    -- changed or deleted by anyone: the trigger in script 10 refuses it.)
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_app') THEN
        FOREACH v_name IN ARRAY c_tables LOOP
            IF NOT has_table_privilege('nexus_app', 'public.' || v_name, 'SELECT,INSERT') THEN
                RAISE EXCEPTION 'nexus_app cannot use table %', v_name;
            END IF;
        END LOOP;
        FOR v_name IN SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = ANY (c_functions) LOOP
            IF NOT has_function_privilege('nexus_app', v_name, 'EXECUTE') THEN
                RAISE EXCEPTION 'nexus_app cannot execute %', v_name;
            END IF;
        END LOOP;
    END IF;
END;
$$;
