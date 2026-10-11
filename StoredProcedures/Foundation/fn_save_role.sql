-- Duplicate role names surface as 23505. The Admin role cannot be deactivated (NX409).
CREATE OR REPLACE FUNCTION fn_save_role(
    p_tenant_id integer, p_role_id integer, p_role_name varchar, p_is_active boolean)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    c_admin_role CONSTANT varchar := 'Admin';
    v_role_id    integer;
    v_old_name   varchar;
BEGIN
    IF p_role_id IS NULL THEN
        INSERT INTO roles (tenant_id, role_name, is_active)
        VALUES (p_tenant_id, p_role_name, p_is_active)
        RETURNING roles.role_id INTO v_role_id;
        RETURN v_role_id;
    END IF;

    SELECT r.role_name INTO v_old_name FROM roles r
     WHERE r.role_id = p_role_id AND r.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Role % not found', p_role_id USING ERRCODE = 'P0002';
    END IF;
    IF v_old_name = c_admin_role AND (p_role_name <> c_admin_role OR NOT p_is_active) THEN
        RAISE EXCEPTION 'The Admin role cannot be renamed or deactivated' USING ERRCODE = 'NX409';
    END IF;

    UPDATE roles SET role_name = p_role_name, is_active = p_is_active, updated_at = now()
     WHERE roles.role_id = p_role_id AND roles.tenant_id = p_tenant_id;
    RETURN p_role_id;
END;
$$;
