-- Cancels an order, only while it is NEW. Nothing was deducted or charged before fulfilment, so there is nothing to
-- undo. The quotation stays 'converted': one order per quotation, ever (uq_orders_quotation), so a cancelled order
-- is followed by "Duplicate as new draft" on the quotation, not by a second order.
--   P0002 not found     - unknown order
--   NX409 rule conflict - the order is fulfilled or already cancelled
-- The row is locked first, so a cancel and a fulfil of the same order queue up and the second one is refused.
CREATE OR REPLACE PROCEDURE sp_cancel_order(p_tenant_id integer, p_order_id bigint, p_cancelled_by integer, p_note varchar)
LANGUAGE plpgsql AS $$
DECLARE
    v_order record;
BEGIN
    SELECT o.order_no, o.status INTO v_order FROM orders o
     WHERE o.order_id = p_order_id AND o.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % not found', p_order_id USING ERRCODE = 'P0002';
    END IF;
    IF v_order.status <> 'new' THEN
        RAISE EXCEPTION 'Order % is already % and cannot be cancelled', v_order.order_no, v_order.status
            USING ERRCODE = 'NX409';
    END IF;
    UPDATE orders SET status = 'cancelled', cancelled_at = now(), updated_at = now()
     WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
    CALL sp_log_order_status(p_tenant_id, p_order_id, 'new', 'cancelled', p_cancelled_by, p_note);
END;
$$;
