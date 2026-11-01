-- After a lead becomes a customer: sets that customer on the lead's quotations that have NONE, so they can be
-- converted to orders. Quotations that already name a customer are never touched, and nothing else about a
-- quotation (lines, prices, status, dates) changes. Each changed quotation gets an audit row in its status log
-- (the same status before and after, with a note saying what happened), so the change is visible on the quotation.
-- Runs inside fn_convert_lead's transaction: if anything fails, the customer, the lead and these quotations all
-- roll back together.
CREATE OR REPLACE PROCEDURE sp_fill_lead_quotations(
    p_tenant_id integer, p_lead_id bigint, p_customer_id bigint, p_user_id integer, p_lead_no varchar)
LANGUAGE plpgsql AS $$
BEGIN
    WITH changed AS (
        UPDATE quotations q
           SET customer_id = p_customer_id, updated_at = now()
         WHERE q.tenant_id = p_tenant_id AND q.lead_id = p_lead_id AND q.customer_id IS NULL
        RETURNING q.quotation_id, q.status)
    INSERT INTO quotation_status_log (tenant_id, quotation_id, from_status, to_status, changed_by, note)
    SELECT p_tenant_id, c.quotation_id, c.status, c.status, p_user_id, 'Customer set from converted lead ' || p_lead_no
      FROM changed c;
END;
$$;
