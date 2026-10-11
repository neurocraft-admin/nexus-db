-- Makes a role's menu_access match its can_view permissions, so the sidebar always agrees with the permission
-- grid. Called by sp_save_role_permissions inside the same transaction. Menu items with no resource (group
-- headings) are only added, never removed here. Kept in sync with 07_foundation_split_role_permission_save.sql.
CREATE OR REPLACE PROCEDURE sp_sync_role_menu_access(p_tenant_id integer, p_role_id integer)
LANGUAGE plpgsql AS $$
BEGIN
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
