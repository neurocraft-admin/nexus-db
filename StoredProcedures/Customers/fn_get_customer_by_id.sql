-- One active customer, or no rows. A deactivated customer is treated as not found (the API returns 404).
CREATE OR REPLACE FUNCTION fn_get_customer_by_id(p_tenant_id integer, p_customer_id bigint)
RETURNS TABLE (customer_id bigint, customer_name varchar, mobile varchar,
               address varchar, credit_balance numeric, is_active boolean)
LANGUAGE sql STABLE AS $$
    SELECT c.customer_id, c.customer_name, c.mobile, c.address, c.credit_balance, c.is_active
      FROM customers c
     WHERE c.tenant_id = p_tenant_id
       AND c.customer_id = p_customer_id
       AND c.is_active;
$$;
