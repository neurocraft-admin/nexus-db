-- Seed data only. No user or password is created here; the API create-admin command does that.
DO $$
DECLARE
    v_tenant_id  CONSTANT integer := 1;   -- single-tenant for now; matches Tenant:DefaultId
    v_admin_id   integer;
    v_users_res  integer;
    v_roles_res  integer;
    v_parent_id  integer;
    v_menu_id    integer;
BEGIN
    -- The Staff role starts with no permissions until an Admin grants them.
    INSERT INTO roles (tenant_id, role_name) VALUES (v_tenant_id, 'Admin'), (v_tenant_id, 'Staff')
    ON CONFLICT (tenant_id, role_name) DO NOTHING;
    SELECT r.role_id INTO v_admin_id FROM roles r WHERE r.tenant_id = v_tenant_id AND r.role_name = 'Admin';

    INSERT INTO resources (tenant_id, resource_code, display_name)
    VALUES (v_tenant_id, 'users', 'Users'), (v_tenant_id, 'roles', 'Roles and permissions')
    ON CONFLICT (tenant_id, resource_code) DO NOTHING;
    SELECT x.resource_id INTO v_users_res FROM resources x WHERE x.tenant_id = v_tenant_id AND x.resource_code = 'users';
    SELECT x.resource_id INTO v_roles_res FROM resources x WHERE x.tenant_id = v_tenant_id AND x.resource_code = 'roles';

    INSERT INTO role_permissions (role_id, resource_id, tenant_id, can_view, can_create, can_update, can_delete)
    VALUES (v_admin_id, v_users_res, v_tenant_id, true, true, true, true),
           (v_admin_id, v_roles_res, v_tenant_id, true, true, true, true)
    ON CONFLICT (role_id, resource_id) DO NOTHING;

    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    SELECT v_tenant_id, NULL, 'Administration', 'settings', NULL, 900, NULL
     WHERE NOT EXISTS (SELECT 1 FROM menu_items m WHERE m.tenant_id = v_tenant_id
                          AND m.parent_id IS NULL AND m.title = 'Administration');
    SELECT m.menu_item_id INTO v_parent_id FROM menu_items m
     WHERE m.tenant_id = v_tenant_id AND m.parent_id IS NULL AND m.title = 'Administration';

    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    VALUES (v_tenant_id, v_parent_id, 'Users', 'people', '/users', 10, v_users_res),
           (v_tenant_id, v_parent_id, 'Roles', 'shield', '/roles', 20, v_roles_res)
    ON CONFLICT (tenant_id, COALESCE(parent_id, 0), title) DO NOTHING;

    FOR v_menu_id IN SELECT m.menu_item_id FROM menu_items m
                      WHERE m.tenant_id = v_tenant_id
                        AND (m.menu_item_id = v_parent_id OR m.parent_id = v_parent_id)
    LOOP
        INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
        VALUES (v_admin_id, v_menu_id, v_tenant_id)
        ON CONFLICT (role_id, menu_item_id) DO NOTHING;
    END LOOP;

    INSERT INTO app_settings (tenant_id, setting_key, setting_value)
    VALUES (v_tenant_id, 'login_max_attempts', '5'),
           (v_tenant_id, 'login_lock_minutes', '15'),
           (v_tenant_id, 'min_password_length', '8')
    ON CONFLICT (tenant_id, setting_key) DO NOTHING;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('02_foundation_seed.sql')
ON CONFLICT DO NOTHING;
