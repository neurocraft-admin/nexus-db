-- Module 6 (Customers). Run after every release. Raises an exception naming the first thing that is missing.
DO $$
DECLARE
    v_name text;
    c_functions CONSTANT text[] := ARRAY[
        'fn_get_customers', 'fn_get_customer_by_id', 'fn_get_customer_by_mobile', 'fn_save_customer',
        'fn_deactivate_customer', 'fn_get_credit_ledger', 'sp_record_credit_charge', 'sp_record_credit_payment'];
BEGIN
    FOREACH v_name IN ARRAY ARRAY['08_customers_schema.sql', '09_customers_menu.sql'] LOOP
        IF NOT EXISTS (SELECT 1 FROM deployment_log d WHERE d.script_name = v_name) THEN
            RAISE EXCEPTION 'Script not applied: %', v_name;
        END IF;
    END LOOP;

    FOREACH v_name IN ARRAY ARRAY['customers', 'customer_credit_ledgers'] LOOP
        IF to_regclass('public.' || v_name) IS NULL THEN
            RAISE EXCEPTION 'Table missing: %', v_name;
        END IF;
    END LOOP;

    FOREACH v_name IN ARRAY c_functions LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = v_name) THEN
            RAISE EXCEPTION 'Function missing: %', v_name;
        END IF;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_customers_mobile') THEN
        RAISE EXCEPTION 'Constraint missing: ck_customers_mobile';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM resources WHERE resource_code = 'customers') THEN
        RAISE EXCEPTION 'Resource missing: customers';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM menu_items WHERE url = '/customers') THEN
        RAISE EXCEPTION 'Menu item missing: /customers';
    END IF;
    IF NOT EXISTS (SELECT 1
                     FROM role_permissions rp
                     JOIN roles r ON r.role_id = rp.role_id
                     JOIN resources x ON x.resource_id = rp.resource_id
                    WHERE r.role_name = 'Admin' AND x.resource_code = 'customers'
                      AND rp.can_view AND rp.can_create AND rp.can_update AND rp.can_delete) THEN
        RAISE EXCEPTION 'Admin does not have full access to customers';
    END IF;

    -- The API connects as nexus_app: it must be able to use what was just created.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_app') THEN
        FOREACH v_name IN ARRAY ARRAY['customers', 'customer_credit_ledgers'] LOOP
            IF NOT has_table_privilege('nexus_app', 'public.' || v_name, 'SELECT,INSERT,UPDATE') THEN
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
SELECT 'customers verification passed' AS result;
