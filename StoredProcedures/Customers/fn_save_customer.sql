-- Insert (p_customer_id NULL) or update. Returns the id.
--   23505 unique_violation  - an ACTIVE customer already has the mobile number (the constraint raises it)
--   NX409 rule conflict     - a DEACTIVATED customer still holds the number; the API maps NX409 to 409 and
--                             shows the message, so the person knows why a number nobody can see is taken
--   P0002 not found         - unknown or deactivated customer on update
-- Updating a deactivated customer is refused (not found) so every read and write agrees it is gone.
CREATE OR REPLACE FUNCTION fn_save_customer(
    p_tenant_id integer, p_customer_id bigint,
    p_customer_name varchar, p_mobile varchar, p_address varchar)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_customer_id   bigint;
    v_holder_active boolean;
BEGIN
    SELECT c.is_active INTO v_holder_active
      FROM customers c
     WHERE c.tenant_id = p_tenant_id AND c.mobile = p_mobile
       AND c.customer_id IS DISTINCT FROM p_customer_id;
    IF FOUND AND NOT v_holder_active THEN
        RAISE EXCEPTION 'A deactivated customer already has this mobile number' USING ERRCODE = 'NX409';
    END IF;

    IF p_customer_id IS NULL THEN
        INSERT INTO customers (tenant_id, customer_name, mobile, address)
        VALUES (p_tenant_id, p_customer_name, p_mobile, p_address)
        RETURNING customers.customer_id INTO v_customer_id;
    ELSE
        UPDATE customers
           SET customer_name = p_customer_name, mobile = p_mobile,
               address = p_address, updated_at = now()
         WHERE customers.customer_id = p_customer_id AND tenant_id = p_tenant_id AND is_active
        RETURNING customers.customer_id INTO v_customer_id;

        IF v_customer_id IS NULL THEN
            RAISE EXCEPTION 'Customer % not found', p_customer_id USING ERRCODE = 'P0002';
        END IF;
    END IF;
    RETURN v_customer_id;
END;
$$;
