-- Module 7 (Tickets): the resources tickets and issue_types, the Service menu group with Tickets, Issue types under
-- Administration, and access. Re-runnable.
--   tickets       view / create / update  - view the list and detail, raise a ticket for a customer; update also changes
--                                           the status and assigns. There is no delete: a ticket is closed, never removed.
--   issue_types   view / create / update  - the issue type maintenance endpoints and screen
-- Admin gets everything. The seeded Staff role gets tickets view and update only (a staff user sees and works only the
-- tickets assigned to them; the API and the database functions enforce that), and no issue_types. Rows that already
-- exist are left alone, so a change made later on the Roles screen is not undone by running this again.
DO $$
DECLARE
    c_tenant_id    CONSTANT integer := 1;    -- single-tenant for now; matches Tenant:DefaultId
    c_group_sort   CONSTANT integer := 400;  -- module menus use 100-800: Customers 100, Inventory 200, Sales 300; Administration stays at 900
    c_issue_sort   CONSTANT integer := 40;   -- after Users (10), Roles (20) and Company (30)
    v_admin_id     integer;
    v_staff_id     integer;
    v_service_id   integer;
    v_admin_group  integer;
    v_tickets_res  integer;
    v_issue_res    integer;
    v_menu_id      integer;
BEGIN
    SELECT r.role_id INTO v_admin_id FROM roles r WHERE r.tenant_id = c_tenant_id AND r.role_name = 'Admin';
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'The Admin role is missing; apply 02_foundation_seed.sql first';
    END IF;
    SELECT r.role_id INTO v_staff_id FROM roles r WHERE r.tenant_id = c_tenant_id AND r.role_name = 'Staff';
    SELECT m.menu_item_id INTO v_admin_group FROM menu_items m
     WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Administration';
    IF v_admin_group IS NULL THEN
        RAISE EXCEPTION 'The Administration menu group is missing; apply 02_foundation_seed.sql first';
    END IF;

    INSERT INTO resources (tenant_id, resource_code, display_name)
    VALUES (c_tenant_id, 'tickets', 'Service tickets'), (c_tenant_id, 'issue_types', 'Issue types')
    ON CONFLICT (tenant_id, resource_code) DO NOTHING;
    SELECT x.resource_id INTO v_tickets_res FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = 'tickets';
    SELECT x.resource_id INTO v_issue_res FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = 'issue_types';

    -- The group heading has no resource: it is shown to a role that can see any of its children.
    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    SELECT c_tenant_id, NULL, 'Service', 'wrench', NULL, c_group_sort, NULL
     WHERE NOT EXISTS (SELECT 1 FROM menu_items m WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Service');
    SELECT m.menu_item_id INTO v_service_id FROM menu_items m
     WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Service';

    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    VALUES (c_tenant_id, v_service_id, 'Tickets', 'ticket', '/service/tickets', 10, v_tickets_res),
           (c_tenant_id, v_admin_group, 'Issue types', 'tag', '/issue-types', c_issue_sort, v_issue_res)
    ON CONFLICT (tenant_id, COALESCE(parent_id, 0), title) DO NOTHING;

    INSERT INTO role_permissions (role_id, resource_id, tenant_id, can_view, can_create, can_update, can_delete)
    VALUES (v_admin_id, v_tickets_res, c_tenant_id, true, true, true, false),
           (v_admin_id, v_issue_res, c_tenant_id, true, true, true, false)
    ON CONFLICT (role_id, resource_id) DO NOTHING;
    -- menu_access for the group heading and for each item the role can reach.
    FOR v_menu_id IN SELECT m.menu_item_id FROM menu_items m
                      WHERE m.tenant_id = c_tenant_id
                        AND (m.menu_item_id = v_service_id OR m.parent_id = v_service_id
                             OR (m.parent_id = v_admin_group AND m.title = 'Issue types'))
    LOOP
        INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
        VALUES (v_admin_id, v_menu_id, c_tenant_id)
        ON CONFLICT (role_id, menu_item_id) DO NOTHING;
    END LOOP;

    IF v_staff_id IS NOT NULL THEN
        INSERT INTO role_permissions (role_id, resource_id, tenant_id, can_view, can_create, can_update, can_delete)
        VALUES (v_staff_id, v_tickets_res, c_tenant_id, true, false, true, false)
        ON CONFLICT (role_id, resource_id) DO NOTHING;
        FOR v_menu_id IN SELECT m.menu_item_id FROM menu_items m
                          WHERE m.tenant_id = c_tenant_id AND (m.menu_item_id = v_service_id OR m.parent_id = v_service_id)
        LOOP
            INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
            VALUES (v_staff_id, v_menu_id, c_tenant_id)
            ON CONFLICT (role_id, menu_item_id) DO NOTHING;
        END LOOP;
    END IF;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('23_tickets_menu.sql')
ON CONFLICT DO NOTHING;
