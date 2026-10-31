-- Module 4 (Packages): the `packages` resource, its sidebar item under Inventory, and Admin access. Re-runnable.
-- Only the Admin role gets it for now; other roles can be granted it from the Roles screen, which lists every
-- resource. Whether cost and margin are hidden from roles that only quote is decided at beta (Open item).
DO $$
DECLARE
    c_tenant_id   CONSTANT integer := 1;   -- single-tenant for now; matches Tenant:DefaultId
    c_menu_sort   CONSTANT integer := 40;  -- after Items (10), Purchases (20) and Stock ledger (30)
    v_admin_id    integer;
    v_parent_id   integer;
    v_resource_id integer;
    v_menu_id     integer;
BEGIN
    SELECT r.role_id INTO v_admin_id FROM roles r WHERE r.tenant_id = c_tenant_id AND r.role_name = 'Admin';
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'The Admin role is missing; apply 02_foundation_seed.sql first';
    END IF;
    SELECT m.menu_item_id INTO v_parent_id FROM menu_items m
     WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Inventory';
    IF v_parent_id IS NULL THEN
        RAISE EXCEPTION 'The Inventory menu group is missing; apply 11_inventory_menu.sql first';
    END IF;

    INSERT INTO resources (tenant_id, resource_code, display_name)
    VALUES (c_tenant_id, 'packages', 'Packages')
    ON CONFLICT (tenant_id, resource_code) DO NOTHING;
    SELECT x.resource_id INTO v_resource_id
      FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = 'packages';

    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    VALUES (c_tenant_id, v_parent_id, 'Packages', 'layers', '/inventory/packages', c_menu_sort, v_resource_id)
    ON CONFLICT (tenant_id, COALESCE(parent_id, 0), title) DO NOTHING;
    SELECT m.menu_item_id INTO v_menu_id
      FROM menu_items m WHERE m.tenant_id = c_tenant_id AND m.parent_id = v_parent_id AND m.title = 'Packages';

    INSERT INTO role_permissions (role_id, resource_id, tenant_id, can_view, can_create, can_update, can_delete)
    VALUES (v_admin_id, v_resource_id, c_tenant_id, true, true, true, true)
    ON CONFLICT (role_id, resource_id) DO NOTHING;

    INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
    VALUES (v_admin_id, v_menu_id, c_tenant_id)
    ON CONFLICT (role_id, menu_item_id) DO NOTHING;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('13_packages_menu.sql')
ON CONFLICT DO NOTHING;
