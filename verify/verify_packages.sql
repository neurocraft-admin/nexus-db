-- Module 4 (Packages). Run after every release. Raises an exception naming the first thing that is missing.
DO $$
DECLARE
    v_name text;
    c_functions CONSTANT text[] := ARRAY[
        'fn_get_packages', 'fn_get_package_by_id', 'fn_get_package_lines', 'fn_set_package_active',
        'fn_get_package_components', 'fn_get_package_availability', 'sp_check_package_lines',
        'sp_replace_package_lines', 'sp_refresh_package_cost', 'sp_save_package', 'sp_duplicate_package'];
BEGIN
    FOREACH v_name IN ARRAY ARRAY['12_packages_schema.sql', '13_packages_menu.sql'] LOOP
        IF NOT EXISTS (SELECT 1 FROM deployment_log d WHERE d.script_name = v_name) THEN
            RAISE EXCEPTION 'Script not applied: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['packages', 'package_lines'] LOOP
        IF to_regclass('public.' || v_name) IS NULL THEN
            RAISE EXCEPTION 'Table missing: %', v_name;
        END IF;
    END LOOP;
    IF to_regclass('public.vw_package_summary') IS NULL THEN
        RAISE EXCEPTION 'View missing: vw_package_summary';
    END IF;
    FOREACH v_name IN ARRAY c_functions LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = v_name) THEN
            RAISE EXCEPTION 'Function missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['ck_packages_price', 'ck_packages_code', 'ck_package_lines_quantity'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = v_name) THEN
            RAISE EXCEPTION 'Constraint missing: %', v_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM resources WHERE resource_code = 'packages') THEN
        RAISE EXCEPTION 'Resource missing: packages';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM menu_items WHERE url = '/inventory/packages' AND parent_id IS NOT NULL) THEN
        RAISE EXCEPTION 'Menu item missing: /inventory/packages';
    END IF;
    IF NOT EXISTS (SELECT 1
                     FROM role_permissions rp
                     JOIN roles r ON r.role_id = rp.role_id
                     JOIN resources x ON x.resource_id = rp.resource_id
                    WHERE r.role_name = 'Admin' AND x.resource_code = 'packages'
                      AND rp.can_view AND rp.can_create AND rp.can_update AND rp.can_delete) THEN
        RAISE EXCEPTION 'Admin does not have full access to packages';
    END IF;
    -- A package always has at least one line.
    IF EXISTS (SELECT 1 FROM packages p
                WHERE NOT EXISTS (SELECT 1 FROM package_lines pl WHERE pl.package_id = p.package_id)) THEN
        RAISE EXCEPTION 'A package has no lines';
    END IF;

    -- The API connects as nexus_app: it must be able to use what was just created.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_app') THEN
        FOREACH v_name IN ARRAY ARRAY['packages', 'package_lines'] LOOP
            IF NOT has_table_privilege('nexus_app', 'public.' || v_name, 'SELECT,INSERT,UPDATE,DELETE') THEN
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
