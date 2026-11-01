-- Validates the lead a quotation is for (see sp_check_quotation_header).
--   P0002 not found     - an unknown lead (COLUMN leadId)
--   NX409 rule conflict - a deactivated lead, or a lead that has already become a customer while the quotation names
--                         no customer (quote the customer instead, so the quotation and the sale stay together)
CREATE OR REPLACE PROCEDURE sp_check_quotation_lead(p_tenant_id integer, p_lead_id bigint, p_customer_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_lead record;
BEGIN
    SELECT l.is_active, l.converted_customer_id, l.lead_no INTO v_lead
      FROM leads l WHERE l.lead_id = p_lead_id AND l.tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lead % not found', p_lead_id USING ERRCODE = 'P0002', COLUMN = 'leadId';
    END IF;
    IF NOT v_lead.is_active OR (v_lead.converted_customer_id IS NOT NULL AND p_customer_id IS NULL) THEN
        RAISE EXCEPTION 'Lead % cannot be quoted: it is deactivated or already a customer', v_lead.lead_no
            USING ERRCODE = 'NX409', COLUMN = 'leadId';
    END IF;
END;
$$;
