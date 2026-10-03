-- The Admin role must always keep view and update on roles AND users, so there is always a screen from which
-- an admin can fix permissions and manage users. Called by sp_save_role_permissions when the role being
-- saved is Admin; raises NX409 otherwise. Kept in sync with 06_foundation_admin_role_keeps_users.sql.
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
