-- Ledger rows for one customer, newest first. The API checks the customer exists (404) before calling this.
CREATE OR REPLACE FUNCTION fn_get_credit_ledger(p_tenant_id integer, p_customer_id bigint)
RETURNS TABLE (ledger_id bigint, entry_type varchar, amount numeric, note varchar,
               created_by integer, created_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT l.ledger_id, l.entry_type, l.amount, l.note, l.created_by, l.created_at
      FROM customer_credit_ledgers l
     WHERE l.tenant_id = p_tenant_id
       AND l.customer_id = p_customer_id
     ORDER BY l.created_at DESC, l.ledger_id DESC;
$$;
