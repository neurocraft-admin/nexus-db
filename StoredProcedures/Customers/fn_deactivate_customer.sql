-- Soft delete. The row is locked so a payment arriving at the same moment cannot slip past the balance check.
--   P0002 not found  - unknown or already deactivated
--   NX409 rule conflict - the balance is not zero ("Customer has an outstanding balance"); the API maps
--                         NX409 to 409. An advance (negative balance) also blocks: settle it first.
CREATE OR REPLACE FUNCTION fn_deactivate_customer(p_tenant_id integer, p_customer_id bigint)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_balance numeric;
BEGIN
    SELECT c.credit_balance INTO v_balance
      FROM customers c
     WHERE c.customer_id = p_customer_id AND c.tenant_id = p_tenant_id AND c.is_active
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer % not found', p_customer_id USING ERRCODE = 'P0002';
    END IF;
    IF v_balance <> 0 THEN
        RAISE EXCEPTION 'Customer has an outstanding balance' USING ERRCODE = 'NX409';
    END IF;

    UPDATE customers SET is_active = false, updated_at = now()
     WHERE customer_id = p_customer_id AND tenant_id = p_tenant_id;
END;
$$;
