-- Finds the customer who has this mobile number or creates one from the lead's details, and says which happened.
-- An existing customer is linked as they are (their name and address are not overwritten). The customer function's
-- own rules apply: p_mobile is already in the stored form. If two people convert at the same moment and the other
-- one creates the customer first, this one finds them instead of failing.
--   NX409 rule conflict - a DEACTIVATED customer still holds the number (the same answer Customers gives, so the
--                         person knows why a number nobody can see is taken)
CREATE OR REPLACE PROCEDURE sp_find_or_create_customer(
    p_tenant_id integer, p_name varchar, p_mobile varchar, p_address varchar,
    OUT p_customer_id bigint, OUT p_was_created boolean)
LANGUAGE plpgsql AS $$
DECLARE
    v_active boolean;
BEGIN
    SELECT c.customer_id, c.is_active INTO p_customer_id, v_active FROM customers c
     WHERE c.tenant_id = p_tenant_id AND c.mobile = p_mobile;
    IF FOUND THEN
        IF NOT v_active THEN
            RAISE EXCEPTION 'A deactivated customer already has this mobile number' USING ERRCODE = 'NX409';
        END IF;
        p_was_created := false;
        RETURN;
    END IF;
    BEGIN
        p_customer_id := fn_save_customer(p_tenant_id, NULL, p_name, p_mobile, p_address);
        p_was_created := true;
    EXCEPTION WHEN unique_violation THEN
        SELECT c.customer_id INTO p_customer_id FROM customers c WHERE c.tenant_id = p_tenant_id AND c.mobile = p_mobile;
        p_was_created := false;
    END;
END;
$$;
