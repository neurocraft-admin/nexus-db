-- The Admin role must keep view and update on users as well as roles (it already kept roles).
-- Re-runnable (CREATE OR REPLACE; no signature changes). The same definitions live in
-- StoredProcedures/Foundation/fn_check_admin_role_permissions.sql and sp_save_role_permissions.sql - keep them in sync.

CREATE OR REPLACE FUNCTION fn_check_admin_role_permissions(p_tenant_id integer, p_permissions jsonb)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    c_required_resources CONSTANT text[] := ARRAY['roles', 'users'];
    v_resource text;
BEGIN
    FOREACH v_resource IN ARRAY c_required_resources LOOP
        IF NOT EXISTS (
            SELECT 1
              FROM jsonb_to_recordset(p_permissions)
                   AS j("resourceId" integer, "canView" boolean, "canUpdate" boolean)
              JOIN resources x ON x.resource_id = j."resourceId" AND x.tenant_id = p_tenant_id
             WHERE x.resource_code = v_resource AND j."canView" AND j."canUpdate") THEN
            RAISE EXCEPTION 'The Admin role must keep view and update on roles and users'
                USING ERRCODE = 'NX409';
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_save_role_permissions(
    p_tenant_id integer, p_role_id integer, p_permissions jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    c_admin_role CONSTANT varchar := 'Admin';
    v_role_name  varchar;
BEGIN
    SELECT r.role_name INTO v_role_name FROM roles r
     WHERE r.role_id = p_role_id AND r.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Role % not found', p_role_id USING ERRCODE = 'P0002';
    END IF;

    IF v_role_name = c_admin_role THEN
        PERFORM fn_check_admin_role_permissions(p_tenant_id, p_permissions);
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

INSERT INTO deployment_log (script_name) VALUES ('06_foundation_admin_role_keeps_users.sql')
ON CONFLICT DO NOTHING;
