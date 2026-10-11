-- For the Customer Support Portal (Module 7): just enough to show "is this you?" - no balance, no mobile
-- echoed back. Active customers only. The public endpoint itself is not part of Module 6.
CREATE OR REPLACE FUNCTION fn_get_customer_by_mobile(p_tenant_id integer, p_mobile varchar)
RETURNS TABLE (customer_id bigint, customer_name varchar, address varchar)
LANGUAGE sql STABLE AS $$
    SELECT c.customer_id, c.customer_name, c.address
      FROM customers c
     WHERE c.tenant_id = p_tenant_id
       AND c.mobile = p_mobile
       AND c.is_active;
$$;
