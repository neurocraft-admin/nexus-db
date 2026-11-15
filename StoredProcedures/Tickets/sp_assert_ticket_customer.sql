-- Checks that a ticket can be raised for this customer: the customer exists in this tenant and is active.
--   P0002 not found     - unknown customer (COLUMN customerId)
--   NX409 rule conflict - a deactivated customer (COLUMN customerId)
CREATE OR REPLACE PROCEDURE sp_assert_ticket_customer(p_tenant_id integer, p_customer_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_active boolean;
BEGIN
    SELECT c.is_active INTO v_active FROM customers c WHERE c.customer_id = p_customer_id AND c.tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer % not found', p_customer_id USING ERRCODE = 'P0002', COLUMN = 'customerId';
    END IF;
    IF NOT v_active THEN
        RAISE EXCEPTION 'This customer is deactivated' USING ERRCODE = 'NX409', COLUMN = 'customerId';
    END IF;
END;
$$;
