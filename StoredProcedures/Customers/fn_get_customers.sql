-- Active customers of a tenant, by name. Deactivated customers are not listed anywhere.
CREATE OR REPLACE FUNCTION fn_get_customers(p_tenant_id integer)
RETURNS TABLE (customer_id bigint, customer_name varchar, mobile varchar,
               address varchar, credit_balance numeric, is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT c.customer_id, c.customer_name, c.mobile, c.address, c.credit_balance, c.is_active
      FROM customers c
     WHERE c.tenant_id = p_tenant_id
       AND c.is_active
     ORDER BY c.customer_name, c.customer_id;
$$;
