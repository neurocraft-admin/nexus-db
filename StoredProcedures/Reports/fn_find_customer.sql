-- The front desk's customer lookup: active customers whose name contains the text, or whose mobile contains the digits typed (3 or more),
-- with what the desk needs to answer a call: the balance, the customer's open ticket (number, status and the technician's FIRST name only, the
-- same minimum the public portal shows) and their latest quotation. The quotation respects p_visible_to like the Quotations screen (a staff
-- user does not see quotations on someone else's lead); NULL = everyone's. A blank search finds nothing.
CREATE OR REPLACE FUNCTION fn_find_customer(p_tenant_id integer, p_search varchar, p_visible_to integer, p_limit integer)
RETURNS TABLE (customer_id bigint, customer_name varchar, mobile varchar, address varchar, credit_balance numeric, open_ticket_no varchar,
               open_ticket_status varchar, open_ticket_technician varchar, last_quotation_no varchar, last_quotation_status varchar)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    c_min_digits CONSTANT integer := 3;
    v_text   text := lower(btrim(COALESCE(p_search, '')));
    v_digits text := regexp_replace(COALESCE(p_search, ''), '[^0-9]', '', 'g');
BEGIN
    IF v_text = '' THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT c.customer_id, c.customer_name, c.mobile, c.address, c.credit_balance, k.ticket_no, k.status, k.technician, q.quotation_no, q.status
      FROM customers c
      LEFT JOIN LATERAL (SELECT t.ticket_no, t.status, NULLIF(split_part(btrim(u.full_name), ' ', 1), '')::varchar AS technician
                           FROM tickets t LEFT JOIN users u ON u.user_id = t.assigned_to
                          WHERE t.tenant_id = p_tenant_id AND t.customer_id = c.customer_id AND t.status IN ('open', 'in_progress')
                          ORDER BY t.created_at DESC LIMIT 1) k ON true
      LEFT JOIN LATERAL (SELECT x.quotation_no, x.status FROM quotations x
                          WHERE x.tenant_id = p_tenant_id AND x.customer_id = c.customer_id
                            AND fn_quotation_visible_to(p_tenant_id, x.quotation_id, p_visible_to)
                          ORDER BY x.created_at DESC, x.quotation_id DESC LIMIT 1) q ON true
     WHERE c.tenant_id = p_tenant_id AND c.is_active
       AND (position(v_text IN lower(c.customer_name)) > 0 OR (length(v_digits) >= c_min_digits AND position(v_digits IN c.mobile) > 0))
     ORDER BY c.customer_name, c.customer_id
     LIMIT p_limit;
END;
$$;
