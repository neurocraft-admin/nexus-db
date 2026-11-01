-- Module 3 (Quotations and orders): the resources quotation_templates, quotations and orders, the Sales menu group
-- with its three screens, and Admin access. Re-runnable.
-- Only the Admin role gets them for now; other roles can be granted them from the Roles screen, which lists
-- every resource.
--   quotation_templates  view / create / update   - templates and their lines
--   quotations           view / create / update   - update also sends, approves, rejects and duplicates
--   orders               view / create / update   - create converts a quotation; update fulfils or cancels
DO $$
DECLARE
    c_tenant_id   CONSTANT integer := 1;   -- single-tenant for now; matches Tenant:DefaultId
    c_menu_sort   CONSTANT integer := 300; -- module menus use 100-800; Administration stays at 900
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
    VALUES (c_tenant_id, 'quotation_templates', 'Quotation templates'),
           (c_tenant_id, 'quotations', 'Quotations'),
           (c_tenant_id, 'orders', 'Orders')
    ON CONFLICT (tenant_id, resource_code) DO NOTHING;

    -- The group heading has no resource: it is shown to a role that can see any of its children.
    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    SELECT c_tenant_id, NULL, 'Sales', 'receipt', NULL, c_menu_sort, NULL
     WHERE NOT EXISTS (SELECT 1 FROM menu_items m WHERE m.tenant_id = c_tenant_id
                          AND m.parent_id IS NULL AND m.title = 'Sales');
    SELECT m.menu_item_id INTO v_parent_id FROM menu_items m
     WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Sales';

    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    SELECT c_tenant_id, v_parent_id, c.title, c.icon, c.url, c.sort_order, x.resource_id
      FROM (VALUES ('Quotations', 'file',      '/sales/quotations', 10, 'quotations'),
                   ('Templates',  'copy',      '/sales/templates',  20, 'quotation_templates'),
                   ('Orders',     'clipboard', '/sales/orders',     30, 'orders')) AS c (title, icon, url, sort_order, code)
      JOIN resources x ON x.tenant_id = c_tenant_id AND x.resource_code = c.code
    ON CONFLICT (tenant_id, COALESCE(parent_id, 0), title) DO NOTHING;

    FOREACH v_code IN ARRAY ARRAY['quotation_templates', 'quotations', 'orders'] LOOP
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

INSERT INTO deployment_log (script_name) VALUES ('15_quotations_menu.sql')
ON CONFLICT DO NOTHING;
