-- The preview of an import: what would happen to each row if it were imported now. It writes nothing. A row is
-- 'ok' or 'rejected' with the reason, and may carry a warning (accepted anyway). On top of fn_parse_import_rows' own
-- checks it looks for duplicates, always on the normalised mobile:
--   * the same mobile earlier in the file: the first valid row wins, later ones are rejected ("same as row N");
--   * a mobile that an open lead already has: rejected, naming that lead;
--   * a mobile that is already a CUSTOMER: accepted, with a warning naming the customer (a repeat buyer is still a lead).
-- fn_import_leads runs this again at the moment of import, so a preview and the import can differ if the data
-- changed in between; the import's answer is the one that counts.
--   22023 invalid parameter - no rows or more than 1000; a default source that is unknown or retired (COLUMN defaultSourceId)
CREATE OR REPLACE FUNCTION fn_check_import_rows(p_tenant_id integer, p_rows jsonb, p_default_source_id integer)
RETURNS TABLE (row_number integer, lead_name text, mobile text, email text, address text, lead_source_id integer,
               expected_value numeric, next_follow_up_date date, notes text, outcome text, reason text, warning text)
LANGUAGE plpgsql AS $$
BEGIN
    CALL sp_assert_import_default_source(p_tenant_id, p_default_source_id);
    RETURN QUERY
    WITH parsed AS (SELECT * FROM fn_parse_import_rows(p_tenant_id, p_rows, p_default_source_id)),
    open_lead AS (
        SELECT p.row_number AS rn, l.lead_no FROM parsed p
          JOIN leads l ON l.tenant_id = p_tenant_id AND l.mobile = p.mobile AND l.is_active AND NOT l.is_closed
         WHERE p.reason IS NULL),
    first_row AS (
        SELECT p.mobile AS mob, min(p.row_number) AS first_rn FROM parsed p
         WHERE p.reason IS NULL AND NOT EXISTS (SELECT 1 FROM open_lead o WHERE o.rn = p.row_number)
         GROUP BY p.mobile)
    SELECT p.row_number, p.lead_name, p.mobile, p.email, p.address, p.lead_source_id, p.expected_value,
           p.next_follow_up_date, p.notes,
           (CASE WHEN COALESCE(p.reason, o.lead_no, CASE WHEN f.first_rn < p.row_number THEN 'x' END) IS NULL THEN 'ok' ELSE 'rejected' END)::text,
           COALESCE(p.reason,
                    CASE WHEN o.lead_no IS NOT NULL THEN 'An open lead (' || o.lead_no || ') already has this mobile number' END,
                    CASE WHEN f.first_rn < p.row_number THEN 'Same mobile as row ' || f.first_rn || ' in this file' END)::text,
           (SELECT 'Already a customer: ' || c.customer_name FROM customers c
             WHERE c.tenant_id = p_tenant_id AND c.mobile = p.mobile LIMIT 1)::text
      FROM parsed p
      LEFT JOIN open_lead o ON o.rn = p.row_number
      LEFT JOIN first_row f ON f.mob = p.mobile AND p.reason IS NULL
     ORDER BY p.row_number;
END;
$$;
