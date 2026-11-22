-- Quotation format: the resources subsidy_slabs and datasheets, their menu entries, and Admin access. Re-runnable.
--   subsidy_slabs  view, create, update  - the subsidy slab table (Administration > Subsidy slabs)
--   datasheets     view, create, update  - the datasheet PDF library (Sales > Datasheets); update also switches a datasheet off
-- Admin gets both. No other role is changed: who else uses them is set on the Roles screen. Rows that already exist are left alone, so a change made
-- later on the Roles screen is not undone by running this again. Choosing datasheets for a quotation needs quotations update, as the rest of the
-- quotation does; the library itself is separate so a role can edit quotations without managing the files.
DO $$
DECLARE
    c_tenant_id CONSTANT integer := 1;    -- single-tenant for now; matches Tenant:DefaultId
    v_admin_id    integer;
    v_slabs_res   integer;
    v_sheets_res  integer;
    v_admin_group integer;
    v_sales_group integer;
    v_menu_id     integer;
BEGIN
    SELECT r.role_id INTO v_admin_id FROM roles r WHERE r.tenant_id = c_tenant_id AND r.role_name = 'Admin';
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'The Admin role is missing; apply 02_foundation_seed.sql first';
    END IF;
    SELECT m.menu_item_id INTO v_admin_group FROM menu_items m WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Administration';
    SELECT m.menu_item_id INTO v_sales_group FROM menu_items m WHERE m.tenant_id = c_tenant_id AND m.parent_id IS NULL AND m.title = 'Sales';
    IF v_admin_group IS NULL OR v_sales_group IS NULL THEN
        RAISE EXCEPTION 'The Administration or Sales menu group is missing; apply 02_foundation_seed.sql and 15_quotations_menu.sql first';
    END IF;

    INSERT INTO resources (tenant_id, resource_code, display_name)
    VALUES (c_tenant_id, 'subsidy_slabs', 'Subsidy slabs'), (c_tenant_id, 'datasheets', 'Datasheets')
    ON CONFLICT (tenant_id, resource_code) DO NOTHING;
    SELECT x.resource_id INTO v_slabs_res FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = 'subsidy_slabs';
    SELECT x.resource_id INTO v_sheets_res FROM resources x WHERE x.tenant_id = c_tenant_id AND x.resource_code = 'datasheets';

    -- Administration after Staff (50); Sales after Templates (20) and before Orders (30).
    INSERT INTO menu_items (tenant_id, parent_id, title, icon, url, sort_order, resource_id)
    VALUES (c_tenant_id, v_admin_group, 'Subsidy slabs', 'tag', '/subsidy-slabs', 60, v_slabs_res),
           (c_tenant_id, v_sales_group, 'Datasheets', 'book', '/sales/datasheets', 25, v_sheets_res)
    ON CONFLICT (tenant_id, COALESCE(parent_id, 0), title) DO NOTHING;

    INSERT INTO role_permissions (role_id, resource_id, tenant_id, can_view, can_create, can_update, can_delete)
    VALUES (v_admin_id, v_slabs_res, c_tenant_id, true, true, true, false),
           (v_admin_id, v_sheets_res, c_tenant_id, true, true, true, false)
    ON CONFLICT (role_id, resource_id) DO NOTHING;
    FOR v_menu_id IN SELECT m.menu_item_id FROM menu_items m
                      WHERE m.tenant_id = c_tenant_id AND m.parent_id IN (v_admin_group, v_sales_group) AND m.title IN ('Subsidy slabs', 'Datasheets')
    LOOP
        INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
        VALUES (v_admin_id, v_menu_id, c_tenant_id)
        ON CONFLICT (role_id, menu_item_id) DO NOTHING;
    END LOOP;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('31_quotation_format_menu.sql')
ON CONFLICT DO NOTHING;
