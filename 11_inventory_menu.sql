-- Module 5 (Inventory): the resources items, purchases and stock, the Inventory menu group with its three
-- screens, and Admin access. Re-runnable.
-- Only the Admin role gets them for now (so only Admin may adjust stock, assumption 3 of the brief); other
-- roles can be granted them from the Roles screen, which lists every resource.
--   items      view / create / update   - the item master and its low-stock list (update also activates)
--   purchases  view / create / update   - purchases, and suppliers (update edits or activates a supplier)
--   stock      view / update            - the movement ledger; update means "make a stock adjustment"
DO $$
DECLARE
    c_tenant_id   CONSTANT integer := 1;   -- single-tenant for now; matches Tenant:DefaultId
    c_menu_sort   CONSTANT integer := 200; -- module menus use 100-800; Administration stays at 900
    v_admin_id    integer;
    v_parent_id   integer;
    v_menu_id     integer;
    v_code        text;
    v_resource_id integer;
BEGIN
    SELECT r.role_id INTO v_admin_id FROM roles r WHERE r.tenant_id = c_tenant_id AND r.role_name = 'Admin';
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'The Admin role is missing; apply 02_foundation_seed.sql first';
    END IF;

    INSERT INTO resources (tenant_id, resource_code, display_name)
    VALUES (c_tenant_id, 'items', 'Items'),
           (c_tenant_id, 'purchases', 'Purchases'),
           (c_tenant_id, 'stock', 'Stock ledger')
    ON CONFLICT (tenant_id, resource_code) DO NOTHING;

    -- The group heading has no resource: it is shown to a role that can see any of its children.
    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    SELECT c_tenant_id, NULL, 'Inventory', 'box', NULL, c_menu_sort, NULL
     WHERE NOT EXISTS (SELECT 1 FROM menu_items m WHERE m.tenant_id = c_tenant_id
                          AND m.parent_id IS NULL AND m.title = 'Inventory');
    SELECT m.menu_item_id INTO v_parent_id FROM menu_items m
     WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Inventory';

    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    SELECT c_tenant_id, v_parent_id, c.title, c.icon, c.url, c.sort_order, x.resource_id
      FROM (VALUES ('Items',        'list', '/inventory/items',     10, 'items'),
                   ('Purchases',    'cart', '/inventory/purchases', 20, 'purchases'),
                   ('Stock ledger', 'book', '/inventory/stock',     30, 'stock')) AS c (title, icon, url, sort_order, code)
      JOIN resources x ON x.tenant_id = c_tenant_id AND x.resource_code = c.code
    ON CONFLICT (tenant_id, COALESCE(parent_id, 0), title) DO NOTHING;

    FOREACH v_code IN ARRAY ARRAY['items', 'purchases', 'stock'] LOOP
        SELECT x.resource_id INTO v_resource_id
          FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = v_code;
        INSERT INTO role_permissions (role_id, resource_id, tenant_id, can_view, can_create, can_update, can_delete)
        VALUES (v_admin_id, v_resource_id, c_tenant_id, true, true, true, true)
        ON CONFLICT (role_id, resource_id) DO NOTHING;
    END LOOP;

    FOR v_menu_id IN SELECT m.menu_item_id FROM menu_items m
                      WHERE m.tenant_id = c_tenant_id
                        AND (m.menu_item_id = v_parent_id OR m.parent_id = v_parent_id)
    LOOP
        INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
        VALUES (v_admin_id, v_menu_id, c_tenant_id)
        ON CONFLICT (role_id, menu_item_id) DO NOTHING;
    END LOOP;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('11_inventory_menu.sql')
ON CONFLICT DO NOTHING;
