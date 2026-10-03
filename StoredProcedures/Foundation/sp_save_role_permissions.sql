-- p_permissions is a JSON array of
--   {"resourceId":1,"canView":true,"canCreate":false,"canUpdate":false,"canDelete":false}
-- Permissions and menu_access change together so the sidebar always matches can_view.
-- Menu items with no resource (such as group headings) are only added, never removed here.
CREATE OR REPLACE PROCEDURE sp_save_role_permissions(
    p_tenant_id integer, p_role_id integer, p_permissions jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    c_admin_role    CONSTANT varchar := 'Admin';
    c_roles_resource CONSTANT varchar := 'roles';
    v_role_name  varchar;
BEGIN
    SELECT r.role_name INTO v_role_name FROM roles r
     WHERE r.role_id = p_role_id AND r.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Role % not found', p_role_id USING ERRCODE = 'P0002';
    END IF;

    -- Stops an Admin locking everyone out of the screen that could fix it.
    IF v_role_name = c_admin_role AND NOT EXISTS (
        SELECT 1
          FROM jsonb_to_recordset(p_permissions)
               AS j("resourceId" integer, "canView" boolean, "canUpdate" boolean)
          JOIN resources x ON x.resource_id = j."resourceId" AND x.tenant_id = p_tenant_id
         WHERE x.resource_code = c_roles_resource AND j."canView" AND j."canUpdate") THEN
        RAISE EXCEPTION 'The Admin role must keep view and update on roles' USING ERRCODE = 'NX409';
    END IF;

    DELETE FROM role_permissions WHERE role_id = p_role_id AND tenant_id = p_tenant_id;

    INSERT INTO role_permissions (role_id, resource_id, tenant_id, can_view, can_create, can_update, can_delete)
    SELECT p_role_id, x.resource_id, p_tenant_id,
           COALESCE(j."canView", false), COALESCE(j."canCreate", false),
           COALESCE(j."canUpdate", false), COALESCE(j."canDelete", false)
      FROM jsonb_to_recordset(p_permissions)
           AS j("resourceId" integer, "canView" boolean, "canCreate" boolean,
                "canUpdate" boolean, "canDelete" boolean)
      JOIN resources x ON x.resource_id = j."resourceId" AND x.tenant_id = p_tenant_id;

    DELETE FROM menu_access ma USING menu_items m
     WHERE ma.menu_item_id = m.menu_item_id AND ma.role_id = p_role_id
       AND ma.tenant_id = p_tenant_id AND m.resource_id IS NOT NULL;

    INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
    SELECT p_role_id, m.menu_item_id, p_tenant_id
      FROM menu_items m
      JOIN role_permissions rp ON rp.resource_id = m.resource_id AND rp.role_id = p_role_id
     WHERE m.tenant_id = p_tenant_id AND rp.can_view
    ON CONFLICT (role_id, menu_item_id) DO NOTHING;

    INSERT INTO menu_access (role_id, menu_item_id, tenant_id)
    SELECT DISTINCT p_role_id, m.parent_id, p_tenant_id
      FROM menu_access ma
      JOIN menu_items m ON m.menu_item_id = ma.menu_item_id
     WHERE ma.role_id = p_role_id AND m.parent_id IS NOT NULL
    ON CONFLICT (role_id, menu_item_id) DO NOTHING;
END;
$$;
