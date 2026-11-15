-- Company profile. Run after every release. Raises an exception naming the first thing that is missing or wrong.
DO $$
DECLARE
    v_name text;
    c_functions CONSTANT text[] := ARRAY[
        'fn_company_value', 'sp_assert_company_text', 'sp_assert_company_format', 'sp_check_company_profile',
        'sp_check_company_bank', 'sp_save_company_profile', 'fn_get_company_profile', 'sp_set_company_logo',
        'fn_get_public_company', 'fn_get_company_logo'];
BEGIN
    FOREACH v_name IN ARRAY ARRAY['20_company_profile_schema.sql', '21_company_profile_menu.sql'] LOOP
        IF NOT EXISTS (SELECT 1 FROM deployment_log d WHERE d.script_name = v_name) THEN
            RAISE EXCEPTION 'Script not applied: %', v_name;
        END IF;
    END LOOP;
    IF to_regclass('public.company_profile') IS NULL THEN
        RAISE EXCEPTION 'Table missing: company_profile';
    END IF;
    FOREACH v_name IN ARRAY c_functions LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = v_name) THEN
            RAISE EXCEPTION 'Function missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['uq_company_profile_tenant', 'ck_company_profile_gstin', 'ck_company_profile_state_matches_gstin',
                                  'ck_company_profile_ifsc', 'ck_company_profile_logo'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = v_name) THEN
            RAISE EXCEPTION 'Constraint missing: %', v_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_company_profile_updated_by') THEN
        RAISE EXCEPTION 'Index missing: ix_company_profile_updated_by';
    END IF;
    -- One row per tenant, and the public function offers the name and the logo flag and nothing else.
    IF EXISTS (SELECT 1 FROM company_profile GROUP BY tenant_id HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'A tenant has more than one company profile row';
    END IF;
    IF (SELECT count(*) FROM fn_get_public_company(1)) <> 1 THEN
        RAISE EXCEPTION 'fn_get_public_company must return exactly one row';
    END IF;
    IF (SELECT pronargs FROM pg_proc WHERE proname = 'fn_get_public_company') <> 1
       OR (SELECT array_length(proargnames, 1) FROM pg_proc WHERE proname = 'fn_get_public_company') <> 3 THEN
        RAISE EXCEPTION 'fn_get_public_company must return only display_name and has_logo';
    END IF;
    -- Admin has the permission, with a menu entry; the API's login (nexus_app) can use what was just created.
    IF NOT EXISTS (SELECT 1 FROM role_permissions rp JOIN roles r ON r.role_id = rp.role_id
                     JOIN resources x ON x.resource_id = rp.resource_id
                    WHERE r.role_name = 'Admin' AND x.resource_code = 'company_profile' AND rp.can_view AND rp.can_update) THEN
        RAISE EXCEPTION 'Admin cannot view and update company_profile';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM menu_items WHERE url = '/company' AND parent_id IS NOT NULL) THEN
        RAISE EXCEPTION 'Menu item missing: /company';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_app') THEN
        IF NOT has_table_privilege('nexus_app', 'public.company_profile', 'SELECT,INSERT,UPDATE') THEN
            RAISE EXCEPTION 'nexus_app cannot use company_profile';
        END IF;
        FOR v_name IN SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = ANY (c_functions) LOOP
            IF NOT has_function_privilege('nexus_app', v_name, 'EXECUTE') THEN
                RAISE EXCEPTION 'nexus_app cannot execute %', v_name;
            END IF;
        END LOOP;
    END IF;
END;
$$;
