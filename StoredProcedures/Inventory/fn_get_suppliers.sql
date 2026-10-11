-- Supplier list; p_active_only hides deactivated suppliers (the purchase form's picker uses it).
CREATE OR REPLACE FUNCTION fn_get_suppliers(p_tenant_id integer, p_active_only boolean)
RETURNS TABLE (supplier_id bigint, supplier_name varchar, mobile varchar, address varchar, is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT s.supplier_id, s.supplier_name, s.mobile, s.address, s.is_active
      FROM suppliers s
     WHERE s.tenant_id = p_tenant_id
       AND (NOT COALESCE(p_active_only, false) OR s.is_active)
     ORDER BY s.supplier_name, s.supplier_id;
$$;
