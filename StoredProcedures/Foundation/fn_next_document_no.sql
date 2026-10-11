CREATE OR REPLACE FUNCTION fn_next_document_no(p_tenant_id integer, p_doc_type varchar)
RETURNS varchar
LANGUAGE plpgsql AS $$
DECLARE
    c_number_width CONSTANT integer := 4;
    v_year  integer := extract(year FROM now())::integer;
    v_no    integer;
BEGIN
    -- The row lock taken by ON CONFLICT DO UPDATE serialises callers, so numbers never repeat.
    INSERT INTO document_counters (tenant_id, doc_type, doc_year, last_no)
    VALUES (p_tenant_id, p_doc_type, v_year, 1)
    ON CONFLICT (tenant_id, doc_type, doc_year)
    DO UPDATE SET last_no = document_counters.last_no + 1, updated_at = now()
    RETURNING last_no INTO v_no;

    RETURN p_doc_type || '-' || v_year || '-' || lpad(v_no::text, c_number_width, '0');
END;
$$;
