-- One order's header (its lines are fn_get_order_lines), with the customer and the quotation it came from.
-- No rows when it does not exist.
CREATE OR REPLACE FUNCTION fn_get_order_by_id(p_tenant_id integer, p_order_id bigint)
RETURNS TABLE (order_id bigint, order_no varchar, quotation_id bigint, quotation_no varchar, customer_id bigint,
               customer_name varchar, customer_mobile varchar, status varchar, payment_mode varchar,
               total_amount numeric, fulfilled_at timestamptz, cancelled_at timestamptz, created_by integer,
               created_by_name varchar, created_at timestamptz, updated_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT o.order_id, o.order_no, o.quotation_id, q.quotation_no, o.customer_id, c.customer_name, c.mobile,
           o.status, o.payment_mode, o.total_amount, o.fulfilled_at, o.cancelled_at, o.created_by, u.full_name,
           o.created_at, o.updated_at
      FROM orders o
      JOIN quotations q ON q.quotation_id = o.quotation_id
      JOIN customers c ON c.customer_id = o.customer_id
      LEFT JOIN users u ON u.user_id = o.created_by AND u.tenant_id = o.tenant_id
     WHERE o.tenant_id = p_tenant_id AND o.order_id = p_order_id;
$$;
