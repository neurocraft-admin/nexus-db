-- Turns an APPROVED quotation into an order (header and lines copied, prices as quoted) and returns the order id.
-- The quotation is set to 'converted' in the same transaction. Safe against a double click: the quotation row is
-- locked first, so the second call waits, sees 'converted' and is refused naming the order that already exists;
-- uq_orders_quotation is the safety net behind it. Nothing is deducted: stock only leaves when the order is
-- fulfilled. Only the lines are copied, so a custom line stays on the order and is skipped at fulfilment.
--   22023 invalid parameter - the quotation has no customer yet (a lead must become a customer first)
--   P0002 not found         - unknown quotation
--   NX409 rule conflict     - not approved, already converted (names the order), or the customer is inactive
CREATE OR REPLACE FUNCTION fn_convert_quotation_to_order(p_tenant_id integer, p_quotation_id bigint, p_created_by integer)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_q        record;
    v_order_id bigint;
BEGIN
    SELECT q.status, q.customer_id, q.total_amount, q.quotation_no INTO v_q FROM quotations q
     WHERE q.quotation_id = p_quotation_id AND q.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quotation % not found', p_quotation_id USING ERRCODE = 'P0002';
    END IF;
    IF v_q.status = 'converted' THEN
        RAISE EXCEPTION 'Quotation % has already been converted to order %', v_q.quotation_no,
            (SELECT o.order_no FROM orders o WHERE o.quotation_id = p_quotation_id) USING ERRCODE = 'NX409';
    END IF;
    IF v_q.status <> 'approved' THEN
        RAISE EXCEPTION 'Only an approved quotation can be converted; this one is %', v_q.status USING ERRCODE = 'NX409';
    END IF;
    IF v_q.customer_id IS NULL THEN
        RAISE EXCEPTION 'The quotation needs a customer before it can be converted' USING ERRCODE = '22023', COLUMN = 'customerId';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = v_q.customer_id AND c.tenant_id = p_tenant_id AND c.is_active) THEN
        RAISE EXCEPTION 'The customer of quotation % is inactive', v_q.quotation_no USING ERRCODE = 'NX409', COLUMN = 'customerId';
    END IF;
    INSERT INTO orders (tenant_id, order_no, quotation_id, customer_id, total_amount, created_by)
    VALUES (p_tenant_id, fn_next_document_no(p_tenant_id, 'ORD'), p_quotation_id, v_q.customer_id, v_q.total_amount, p_created_by)
    RETURNING orders.order_id INTO v_order_id;
    INSERT INTO order_lines (tenant_id, order_id, line_type, item_id, package_id, description, unit, quantity,
                             unit_price, line_total, sort_order)
    SELECT l.tenant_id, v_order_id, l.line_type, l.item_id, l.package_id, l.description, l.unit, l.quantity,
           l.unit_price, l.line_total, l.sort_order
      FROM quotation_lines l WHERE l.quotation_id = p_quotation_id AND l.tenant_id = p_tenant_id;
    UPDATE quotations SET status = 'converted', updated_at = now() WHERE quotation_id = p_quotation_id AND tenant_id = p_tenant_id;
    CALL sp_log_quotation_status(p_tenant_id, p_quotation_id, 'approved', 'converted', p_created_by, 'Order created');
    CALL sp_log_order_status(p_tenant_id, v_order_id, NULL, 'new', p_created_by, 'Created from ' || v_q.quotation_no);
    RETURN v_order_id;
END;
$$;
