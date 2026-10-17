-- Deactivate or reactivate a package. Old quotations keep their own copy of the price and description, so this
-- never touches them. Reactivating a package with an inactive component is allowed; it shows "Needs attention".
--   P0002 not found
CREATE OR REPLACE FUNCTION fn_set_package_active(p_tenant_id integer, p_package_id bigint, p_is_active boolean)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE packages
       SET is_active = p_is_active, updated_at = now()
     WHERE package_id = p_package_id AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Package % not found', p_package_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;
