-- One quotation's header (its lines are fn_get_quotation_lines): customer, template, the quotation it was copied
-- from, the order it became, and who created it. No rows when it does not exist.
CREATE OR REPLACE FUNCTION fn_get_quotation_by_id(p_tenant_id integer, p_quotation_id bigint)
RETURNS TABLE (quotation_id bigint, quotation_no varchar, customer_id bigint, customer_name varchar,
               customer_mobile varchar, lead_id bigint, template_id bigint, template_name varchar,
               revision_of_id bigint, revision_of_no varchar, status varchar, quotation_date date, valid_until date,
               subtotal numeric, discount_amount numeric, total_amount numeric, terms_text varchar, notes varchar,
               created_by integer, created_by_name varchar, sent_at timestamptz, decided_at timestamptz,
               order_id bigint, order_no varchar, created_at timestamptz, updated_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT q.quotation_id, q.quotation_no, q.customer_id, c.customer_name, c.mobile, q.lead_id, q.template_id,
           t.template_name, q.revision_of_id, r.quotation_no, q.status, q.quotation_date, q.valid_until, q.subtotal,
           q.discount_amount, q.total_amount, q.terms_text, q.notes, q.created_by, u.full_name, q.sent_at,
           q.decided_at, o.order_id, o.order_no, q.created_at, q.updated_at
      FROM quotations q
      LEFT JOIN customers c ON c.customer_id = q.customer_id
      LEFT JOIN quotation_templates t ON t.template_id = q.template_id
      LEFT JOIN quotations r ON r.quotation_id = q.revision_of_id
      LEFT JOIN users u ON u.user_id = q.created_by AND u.tenant_id = q.tenant_id
      LEFT JOIN orders o ON o.quotation_id = q.quotation_id
     WHERE q.tenant_id = p_tenant_id AND q.quotation_id = p_quotation_id;
$$;
