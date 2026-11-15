-- Module 8 (Staff and tasks): the resources staff, tasks and my_work, the menu entries, and access. Re-runnable.
--   staff    view / create / update  - the Staff screen (staff-type users and their profiles)
--   tasks    view / create / update  - the Tasks screen: all tasks, create, edit, assign, cancel
--   my_work  view / update           - the worker's own work: view it, start and complete their own tasks. A role that has
--                                      my_work view is what makes a staff user ASSIGNABLE (they can see what they are given).
-- Admin gets everything. The seeded Staff role gets my_work view and update (it keeps the tickets view and update from script 23).
-- Rows that already exist are left alone, so a change made later on the Roles screen is not undone by running this again.
-- Menu: Tasks and "My work" under Service, Staff under Administration. "My work" (url /staff) is the mobile dashboard, so a
-- staff user who signs in on the admin login can reach it.
DO $$
DECLARE
    c_tenant_id   CONSTANT integer := 1;    -- single-tenant for now; matches Tenant:DefaultId
    c_work_sort   CONSTANT integer := 5;    -- My work first in Service, before Tickets (10) and Tasks (20)
    c_tasks_sort  CONSTANT integer := 20;
    c_staff_sort  CONSTANT integer := 50;   -- after Users (10), Roles (20), Company (30) and Issue types (40)
    v_admin_id     integer;
    v_staff_id     integer;
    v_service_id   integer;
    v_admin_group  integer;
    v_staff_res    integer;
    v_tasks_res    integer;
    v_work_res     integer;
    v_menu_id      integer;
BEGIN
    SELECT r.role_id INTO v_admin_id FROM roles r WHERE r.tenant_id = c_tenant_id AND r.role_name = 'Admin';
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'The Admin role is missing; apply 02_foundation_seed.sql first';
    END IF;
    SELECT r.role_id INTO v_staff_id FROM roles r WHERE r.tenant_id = c_tenant_id AND r.role_name = 'Staff';
    SELECT m.menu_item_id INTO v_service_id FROM menu_items m
     WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Service';
    SELECT m.menu_item_id INTO v_admin_group FROM menu_items m
     WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Administration';
    IF v_service_id IS NULL OR v_admin_group IS NULL THEN
        RAISE EXCEPTION 'The Service or Administration menu group is missing; apply 02_foundation_seed.sql and 23_tickets_menu.sql first';
    END IF;

    INSERT INTO resources (tenant_id, resource_code, display_name)
    VALUES (c_tenant_id, 'staff', 'Staff'), (c_tenant_id, 'tasks', 'Tasks'), (c_tenant_id, 'my_work', 'My work')
    ON CONFLICT (tenant_id, resource_code) DO NOTHING;
    SELECT x.resource_id INTO v_staff_res FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = 'staff';
    SELECT x.resource_id INTO v_tasks_res FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = 'tasks';
    SELECT x.resource_id INTO v_work_res FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = 'my_work';

    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    VALUES (c_tenant_id, v_service_id, 'My work', 'briefcase', '/staff', c_work_sort, v_work_res),
           (c_tenant_id, v_service_id, 'Tasks', 'calendar', '/service/tasks', c_tasks_sort, v_tasks_res),
           (c_tenant_id, v_admin_group, 'Staff', 'id-card', '/staff-members', c_staff_sort, v_staff_res)
    ON CONFLICT (tenant_id, COALESCE(parent_id, 0), title) DO NOTHING;

    INSERT INTO role_permissions (role_id, resource_id, tenant_id, can_view, can_create, can_update, can_delete)
    VALUES (v_admin_id, v_staff_res, c_tenant_id, true, true, true, false),
           (v_admin_id, v_tasks_res, c_tenant_id, true, true, true, false),
           (v_admin_id, v_work_res, c_tenant_id, true, false, true, false)
    ON CONFLICT (role_id, resource_id) DO NOTHING;
    FOR v_menu_id IN SELECT m.menu_item_id FROM menu_items m
                      WHERE m.tenant_id = c_tenant_id AND m.title IN ('My work', 'Tasks', 'Staff') AND m.parent_id IN (v_service_id, v_admin_group)
    LOOP
        INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
        VALUES (v_admin_id, v_menu_id, c_tenant_id)
        ON CONFLICT (role_id, menu_item_id) DO NOTHING;
    END LOOP;

    IF v_staff_id IS NOT NULL THEN
        INSERT INTO role_permissions (role_id, resource_id, tenant_id, can_view, can_create, can_update, can_delete)
        VALUES (v_staff_id, v_work_res, c_tenant_id, true, false, true, false)
        ON CONFLICT (role_id, resource_id) DO NOTHING;
        INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
        SELECT v_staff_id, m.menu_item_id, c_tenant_id FROM menu_items m
         WHERE m.tenant_id = c_tenant_id AND m.parent_id = v_service_id AND m.title = 'My work'
        ON CONFLICT (role_id, menu_item_id) DO NOTHING;
    END IF;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('26_staff_menu.sql')
ON CONFLICT DO NOTHING;
