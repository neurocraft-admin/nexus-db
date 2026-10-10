-- Adds a 'charge' row and increases the balance (the customer owes more) in one transaction.
-- Module 3 will call this when an order is fulfilled on credit. P0002 when the customer is unknown or
-- deactivated. A non-positive amount is refused by the ledger CHECK (the API validates it first).
CREATE OR REPLACE PROCEDURE sp_record_credit_charge(
    p_tenant_id integer, p_customer_id bigint,
    p_amount numeric, p_note varchar, p_created_by integer)
LANGUAGE plpgsql AS $$
BEGIN
    -- Lock the row so two simultaneous entries cannot overwrite each other's balance.
    PERFORM 1 FROM customers
     WHERE customer_id = p_customer_id AND tenant_id = p_tenant_id AND is_active
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer % not found', p_customer_id USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO customer_credit_ledgers (tenant_id, customer_id, entry_type, amount, note, created_by)
    VALUES (p_tenant_id, p_customer_id, 'charge', p_amount, p_note, p_created_by);

    UPDATE customers
       SET credit_balance = credit_balance + p_amount, updated_at = now()
     WHERE customer_id = p_customer_id AND tenant_id = p_tenant_id;
END;
$$;
