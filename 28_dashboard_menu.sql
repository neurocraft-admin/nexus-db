-- Module 11 (Dashboard and reports): the resources dashboard and reports, the menu entries, and access. Re-runnable.
--   dashboard  view  - open the dashboard (the landing page). What the page then SHOWS depends on the user's other permissions
--                      (leads, quotations, orders, items, tickets, tasks, staff, customers) and on the user type.
--   reports    view  - the three reports (quotation conversion, inventory movement, ticket resolution): company-wide
-- Admin gets both. No other role is changed: who else sees the dashboard is set on the Roles screen. Rows that already exist
-- are left alone, so a change made later on the Roles screen is not undone by running this again.
-- Menu: Dashboard at the top (sort 50, before Customers 100) and a Reports group before Administration (900) holding the three reports.
DO $$
DECLARE
    c_tenant_id    CONSTANT integer := 1;    -- single-tenant for now; matches Tenant:DefaultId
    c_dashboard_sort CONSTANT integer := 50;
    c_reports_sort   CONSTANT integer := 850;
    v_admin_id     integer;
    v_dash_res     integer;
    v_reports_res  integer;
    v_group_id     integer;
    v_menu_id      integer;
BEGIN
    SELECT r.role_id INTO v_admin_id FROM roles r WHERE r.tenant_id = c_tenant_id AND r.role_name = 'Admin';
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'The Admin role is missing; apply 02_foundation_seed.sql first';
    END IF;

    INSERT INTO resources (tenant_id, resource_code, display_name)
    VALUES (c_tenant_id, 'dashboard', 'Dashboard'), (c_tenant_id, 'reports', 'Reports')
    ON CONFLICT (tenant_id, resource_code) DO NOTHING;
    SELECT x.resource_id INTO v_dash_res FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = 'dashboard';
    SELECT x.resource_id INTO v_reports_res FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = 'reports';

    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    SELECT c_tenant_id, NULL, 'Dashboard', 'chart', '/dashboard', c_dashboard_sort, v_dash_res
     WHERE NOT EXISTS (SELECT 1 FROM menu_items m WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Dashboard');
    -- The group heading has no resource: it is shown to a role that can see any of its children.
    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    SELECT c_tenant_id, NULL, 'Reports', 'chart', NULL, c_reports_sort, NULL
     WHERE NOT EXISTS (SELECT 1 FROM menu_items m WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Reports');
    SELECT m.menu_item_id INTO v_group_id FROM menu_items m
     WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Reports';

    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    VALUES (c_tenant_id, v_group_id, 'Quotation conversion', 'receipt', '/reports/quotation-conversion', 10, v_reports_res),
           (c_tenant_id, v_group_id, 'Inventory movement', 'layers', '/reports/inventory-movement', 20, v_reports_res),
           (c_tenant_id, v_group_id, 'Ticket resolution', 'wrench', '/reports/ticket-resolution', 30, v_reports_res)
    ON CONFLICT (tenant_id, COALESCE(parent_id, 0), title) DO NOTHING;

    INSERT INTO role_permissions (role_id, resource_id, tenant_id, can_view, can_create, can_update, can_delete)
    VALUES (v_admin_id, v_dash_res, c_tenant_id, true, false, false, false),
           (v_admin_id, v_reports_res, c_tenant_id, true, false, false, false)
    ON CONFLICT (role_id, resource_id) DO NOTHING;
    FOR v_menu_id IN SELECT m.menu_item_id FROM menu_items m
                      WHERE m.tenant_id = c_tenant_id
                        AND ((m.parent_id IS NULL AND m.title IN ('Dashboard', 'Reports')) OR m.parent_id = v_group_id)
    LOOP
        INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
        VALUES (v_admin_id, v_menu_id, c_tenant_id)
        ON CONFLICT (role_id, menu_item_id) DO NOTHING;
    END LOOP;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('28_dashboard_menu.sql')
ON CONFLICT DO NOTHING;
