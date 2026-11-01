-- The quotation list, newest first, with filters and paging. Each row also carries total_count (rows matching the
-- filter before paging) so the caller can show "page x of y". p_status, p_customer_id, p_from, p_to and p_search are
-- all optional (NULL = no filter). p_from / p_to are quotation dates, inclusive. p_search matches the quotation
-- number or the customer name anywhere, ignoring case (plain text, no wildcards). p_limit NULL returns everything
-- (the API caps what it asks for). order_id / order_no show the order a converted quotation became.
CREATE OR REPLACE FUNCTION fn_get_quotations(
    p_tenant_id integer, p_status varchar, p_customer_id bigint, p_from date, p_to date, p_search varchar,
    p_limit integer, p_offset integer)
RETURNS TABLE (quotation_id bigint, quotation_no varchar, customer_id bigint, customer_name varchar, lead_id bigint,
               status varchar, quotation_date date, valid_until date, subtotal numeric, discount_amount numeric,
               total_amount numeric, line_count bigint, revision_of_id bigint, order_id bigint, order_no varchar,
               created_at timestamptz, total_count bigint)
LANGUAGE sql STABLE AS $$
    SELECT q.quotation_id, q.quotation_no, q.customer_id, c.customer_name, q.lead_id, q.status, q.quotation_date,
           q.valid_until, q.subtotal, q.discount_amount, q.total_amount,
           (SELECT count(*) FROM quotation_lines l WHERE l.quotation_id = q.quotation_id),
           q.revision_of_id, o.order_id, o.order_no, q.created_at, count(*) OVER ()
      FROM quotations q
      LEFT JOIN customers c ON c.customer_id = q.customer_id
      LEFT JOIN orders o ON o.quotation_id = q.quotation_id
     WHERE q.tenant_id = p_tenant_id
       AND (p_status IS NULL OR q.status = p_status)
       AND (p_customer_id IS NULL OR q.customer_id = p_customer_id)
       AND (p_from IS NULL OR q.quotation_date >= p_from)
       AND (p_to IS NULL OR q.quotation_date <= p_to)
       AND (p_search IS NULL OR btrim(p_search) = ''
            OR position(lower(btrim(p_search)) IN lower(q.quotation_no || ' ' || COALESCE(c.customer_name, ''))) > 0)
     ORDER BY q.quotation_date DESC, q.quotation_id DESC
     LIMIT p_limit OFFSET COALESCE(p_offset, 0);
$$;
