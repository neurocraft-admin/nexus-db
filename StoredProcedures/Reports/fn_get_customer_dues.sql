-- Who owes money and how late they are, for every customer with a positive balance. Payments settle the OLDEST charges first, so the
-- unpaid part of a balance belongs to the newest charges: the oldest charge that is still (partly) unpaid is found by adding charges up from
-- the newest until the balance is covered. days_overdue = days since that charge's due day (its business day plus credit_terms_days, default
-- 30); 0 when it is not yet due, or when the balance has no charge behind it. A customer with an advance (negative balance) is not listed.
CREATE OR REPLACE FUNCTION fn_get_customer_dues(p_tenant_id integer, p_as_of date)
RETURNS TABLE (customer_id bigint, customer_name varchar, mobile varchar, balance numeric, oldest_unpaid_at timestamptz, days_overdue integer)
LANGUAGE sql STABLE AS $$
    WITH terms AS (
        SELECT COALESCE(CASE WHEN fn_get_setting(p_tenant_id, 'credit_terms_days') ~ '^[0-9]{1,4}$'
                             THEN fn_get_setting(p_tenant_id, 'credit_terms_days')::integer END, 30) AS days
    ), owing AS (
        SELECT c.customer_id, c.customer_name, c.mobile, c.credit_balance FROM customers c
         WHERE c.tenant_id = p_tenant_id AND c.credit_balance > 0
    ), charges AS (
        SELECT l.customer_id, l.created_at, l.amount,
               sum(l.amount) OVER (PARTITION BY l.customer_id ORDER BY l.created_at DESC, l.ledger_id DESC) AS newest_first_total
          FROM customer_credit_ledgers l JOIN owing o ON o.customer_id = l.customer_id
         WHERE l.tenant_id = p_tenant_id AND l.entry_type = 'charge'
    ), oldest AS (
        SELECT ch.customer_id, min(ch.created_at) AS created_at
          FROM charges ch JOIN owing o ON o.customer_id = ch.customer_id
         WHERE ch.newest_first_total - ch.amount < o.credit_balance GROUP BY ch.customer_id
    )
    SELECT o.customer_id, o.customer_name, o.mobile, o.credit_balance, od.created_at,
           COALESCE(greatest(0, p_as_of - (fn_business_date_of(p_tenant_id, od.created_at) + t.days)), 0)
      FROM owing o CROSS JOIN terms t LEFT JOIN oldest od ON od.customer_id = o.customer_id;
$$;
