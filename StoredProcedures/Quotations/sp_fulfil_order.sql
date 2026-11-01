-- Fulfils a NEW order in ONE transaction: the whole order is checked, stock goes out for every item line and every
-- package component, and for payment_mode 'credit' the order total is charged to the customer's credit balance
-- (sp_record_credit_charge: ledger row and balance together). Any failure rolls back everything, stock and ledger
-- included; an order is fulfilled completely or not at all. Custom lines need no stock.
-- Credit limit: none exists. Customers have no credit-limit column and sp_record_credit_charge never refuses a
-- charge, so a credit order is accepted whatever the customer already owes (a zero-total order adds no ledger row).
-- The order row is locked first, then the customer, then the items in id order (sp_check_order_stock), so two
-- simultaneous fulfilments of one order queue up and the second is refused as already fulfilled.
--   22023 invalid parameter - payment mode is not 'paid' or 'credit' (COLUMN paymentMode)
--   P0002 not found         - unknown order
--   NX409 rule conflict     - the order is not new; an inactive customer; an inactive item or component
--   NX411 insufficient stock - one or more items short (DETAIL lists them all, see sp_check_order_stock)
CREATE OR REPLACE PROCEDURE sp_fulfil_order(
    p_tenant_id integer, p_order_id bigint, p_payment_mode varchar, p_fulfilled_by integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_order record;
BEGIN
    IF p_payment_mode IS NULL OR p_payment_mode NOT IN ('paid', 'credit') THEN
        RAISE EXCEPTION 'Payment mode must be paid or credit' USING ERRCODE = '22023', COLUMN = 'paymentMode';
    END IF;
    SELECT o.order_no, o.status, o.customer_id, o.total_amount INTO v_order FROM orders o
     WHERE o.order_id = p_order_id AND o.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % not found', p_order_id USING ERRCODE = 'P0002';
    END IF;
    IF v_order.status <> 'new' THEN
        RAISE EXCEPTION 'Order % is already %', v_order.order_no, v_order.status USING ERRCODE = 'NX409';
    END IF;
    PERFORM 1 FROM customers c WHERE c.customer_id = v_order.customer_id AND c.tenant_id = p_tenant_id AND c.is_active FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'The customer of order % is inactive', v_order.order_no USING ERRCODE = 'NX409', COLUMN = 'customerId';
    END IF;
    CALL sp_check_order_stock(p_tenant_id, p_order_id);
    CALL sp_take_order_stock(p_tenant_id, p_order_id, v_order.order_no, p_fulfilled_by);
    IF p_payment_mode = 'credit' AND v_order.total_amount > 0 THEN
        CALL sp_record_credit_charge(p_tenant_id, v_order.customer_id, v_order.total_amount,
                                     ('Order ' || v_order.order_no)::varchar, p_fulfilled_by);
    END IF;
    UPDATE orders SET status = 'fulfilled', payment_mode = p_payment_mode, fulfilled_at = now(), updated_at = now()
     WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
    CALL sp_log_order_status(p_tenant_id, p_order_id, 'new', 'fulfilled', p_fulfilled_by, 'Payment: ' || p_payment_mode);
END;
$$;
