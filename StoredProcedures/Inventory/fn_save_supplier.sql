-- Insert (p_supplier_id NULL) or update a supplier. Returns the id.
--   23505 unique_violation  - a supplier with this name already exists, ignoring case (uq_suppliers_tenant_name)
--   23514 check violation   - mobile is not ten digits starting 6-9 (the API normalises it first)
--   P0002 not found         - unknown supplier on update
CREATE OR REPLACE FUNCTION fn_save_supplier(
    p_tenant_id integer, p_supplier_id bigint, p_supplier_name varchar, p_mobile varchar, p_address varchar)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_supplier_id bigint;
BEGIN
    IF p_supplier_id IS NULL THEN
        INSERT INTO suppliers (tenant_id, supplier_name, mobile, address)
        VALUES (p_tenant_id, p_supplier_name, p_mobile, p_address)
        RETURNING suppliers.supplier_id INTO v_supplier_id;
    ELSE
        UPDATE suppliers
           SET supplier_name = p_supplier_name, mobile = p_mobile, address = p_address, updated_at = now()
         WHERE suppliers.supplier_id = p_supplier_id AND suppliers.tenant_id = p_tenant_id
        RETURNING suppliers.supplier_id INTO v_supplier_id;

        IF v_supplier_id IS NULL THEN
            RAISE EXCEPTION 'Supplier % not found', p_supplier_id USING ERRCODE = 'P0002';
        END IF;
    END IF;
    RETURN v_supplier_id;
END;
$$;
