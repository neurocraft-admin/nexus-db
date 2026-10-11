-- One supplier, active or not.
CREATE OR REPLACE FUNCTION fn_get_supplier_by_id(p_tenant_id integer, p_supplier_id bigint)
RETURNS TABLE (supplier_id bigint, supplier_name varchar, mobile varchar, address varchar, is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT s.supplier_id, s.supplier_name, s.mobile, s.address, s.is_active
      FROM suppliers s
     WHERE s.tenant_id = p_tenant_id
       AND s.supplier_id = p_supplier_id;
$$;
