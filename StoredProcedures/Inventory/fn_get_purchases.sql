-- Purchase list, newest first. p_from / p_to filter on purchase_date (inclusive; NULL means no limit).
CREATE OR REPLACE FUNCTION fn_get_purchases(p_tenant_id integer, p_from date, p_to date)
RETURNS TABLE (purchase_id bigint, purchase_no varchar, supplier_id bigint, supplier_name varchar,
               purchase_date date, reference_text varchar, total_amount numeric, line_count bigint,
               created_by integer, created_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT p.purchase_id, p.purchase_no, p.supplier_id, s.supplier_name, p.purchase_date, p.reference_text,
           p.total_amount,
           (SELECT count(*) FROM purchase_lines pl WHERE pl.purchase_id = p.purchase_id),
           p.created_by, p.created_at
      FROM purchases p
      LEFT JOIN suppliers s ON s.supplier_id = p.supplier_id
     WHERE p.tenant_id = p_tenant_id
       AND (p_from IS NULL OR p.purchase_date >= p_from)
       AND (p_to IS NULL OR p.purchase_date <= p_to)
     ORDER BY p.purchase_date DESC, p.purchase_id DESC;
$$;
