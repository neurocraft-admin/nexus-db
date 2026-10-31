-- The revision chain a quotation belongs to: walk up through revision_of_id to the first quotation, then list it and
-- everything copied from it (and from those copies), oldest first. depth 1 is the original. is_current marks the
-- quotation that was asked about. A quotation that was never copied and is not a copy returns just itself. If one
-- quotation was duplicated twice, its two copies are siblings at the same depth.
CREATE OR REPLACE FUNCTION fn_get_quotation_revisions(p_tenant_id integer, p_quotation_id bigint)
RETURNS TABLE (quotation_id bigint, quotation_no varchar, status varchar, revision_of_id bigint,
               quotation_date date, total_amount numeric, depth integer, is_current boolean)
LANGUAGE sql STABLE AS $$
    WITH RECURSIVE up AS (
        SELECT q.quotation_id, q.revision_of_id FROM quotations q
         WHERE q.tenant_id = p_tenant_id AND q.quotation_id = p_quotation_id
        UNION ALL
        SELECT p.quotation_id, p.revision_of_id FROM quotations p
          JOIN up ON p.quotation_id = up.revision_of_id
         WHERE p.tenant_id = p_tenant_id),
    down AS (
        SELECT u.quotation_id, 1 AS depth FROM up u WHERE u.revision_of_id IS NULL
        UNION ALL
        SELECT c.quotation_id, d.depth + 1 FROM quotations c
          JOIN down d ON c.revision_of_id = d.quotation_id
         WHERE c.tenant_id = p_tenant_id)
    SELECT q.quotation_id, q.quotation_no, q.status, q.revision_of_id, q.quotation_date, q.total_amount,
           d.depth, q.quotation_id = p_quotation_id
      FROM down d
      JOIN quotations q ON q.quotation_id = d.quotation_id
     ORDER BY d.depth, q.quotation_id;
$$;
