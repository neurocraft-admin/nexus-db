-- Deactivate or reactivate a supplier. Past purchases keep pointing at it; new purchases refuse an inactive one.
--   P0002 not found
CREATE OR REPLACE FUNCTION fn_set_supplier_active(p_tenant_id integer, p_supplier_id bigint, p_is_active boolean)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE suppliers
       SET is_active = p_is_active, updated_at = now()
     WHERE supplier_id = p_supplier_id AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier % not found', p_supplier_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;
