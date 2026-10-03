-- Run after every release. Raises an exception naming the first thing that is missing.
DO $$
DECLARE
    v_name text;
BEGIN
    FOREACH v_name IN ARRAY ARRAY['00_deployment_log.sql', '01_foundation_schema.sql', '02_foundation_seed.sql',
                                  '03_foundation_grants.sql', '04_foundation_last_admin_guard.sql'] LOOP
        IF NOT EXISTS (SELECT 1 FROM deployment_log d WHERE d.script_name = v_name) THEN
            RAISE EXCEPTION 'Script not applied: %', v_name;
        END IF;
    END LOOP;

    FOREACH v_name IN ARRAY ARRAY['roles', 'users', 'resources', 'role_permissions', 'menu_items',
                                  'menu_access', 'app_settings', 'document_counters'] LOOP
        IF to_regclass('public.' || v_name) IS NULL THEN
            RAISE EXCEPTION 'Table missing: %', v_name;
        END IF;
    END LOOP;

    FOREACH v_name IN ARRAY ARRAY['fn_get_user_for_login', 'sp_record_login_success', 'sp_record_login_failure',
            'fn_get_user_permissions', 'fn_get_menu_for_user', 'fn_next_document_no', 'fn_get_setting',
            'fn_get_users', 'fn_save_user', 'fn_set_user_active', 'sp_reset_user_password', 'sp_change_password',
            'fn_check_admin_demotion', 'fn_get_roles', 'fn_save_role', 'fn_get_role_permissions', 'sp_save_role_permissions'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = v_name) THEN
            RAISE EXCEPTION 'Function missing: %', v_name;
        END IF;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM roles WHERE role_name = 'Admin') THEN
        RAISE EXCEPTION 'Seed missing: Admin role';
    END IF;
    IF EXISTS (SELECT 1 FROM users WHERE password_hash = '') THEN
        RAISE EXCEPTION 'A user has an empty password hash';
    END IF;
END;
$$;
SELECT 'foundation verification passed' AS result;
