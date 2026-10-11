-- p_permissions is a JSON array of
--   {"resourceId":1,"canView":true,"canCreate":false,"canUpdate":false,"canDelete":false}
-- Permissions and menu_access change together (sp_sync_role_menu_access) so the sidebar always matches can_view.
-- Saving the Admin role goes through fn_check_admin_role_permissions first (roles and users stay manageable).
-- Kept in sync with 07_foundation_split_role_permission_save.sql.
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

    CALL sp_sync_role_menu_access(p_tenant_id, p_role_id);
END;
$$;
