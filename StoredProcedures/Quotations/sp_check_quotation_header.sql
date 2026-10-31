-- Validates the header of a quotation before it is saved. Each RAISE names the request field with COLUMN.
--   22023 invalid parameter - no customer or lead, a valid-until before the quotation date, a discount that is
--                             negative or has more than 2 decimals
--   P0002 not found         - an unknown customer or template
--   NX409 rule conflict     - an inactive customer
CREATE OR REPLACE PROCEDURE sp_check_quotation_header(
    p_tenant_id integer, p_customer_id bigint, p_lead_id bigint, p_template_id bigint,
    p_quotation_date date, p_valid_until date, p_discount_amount numeric)
LANGUAGE plpgsql AS $$
DECLARE
    v_active boolean;
BEGIN
    IF p_customer_id IS NULL AND p_lead_id IS NULL THEN
        RAISE EXCEPTION 'A quotation needs a customer' USING ERRCODE = '22023', COLUMN = 'customerId';
    END IF;
    IF p_quotation_date IS NULL OR p_valid_until IS NULL OR p_valid_until < p_quotation_date THEN
        RAISE EXCEPTION 'The valid-until date cannot be before the quotation date' USING ERRCODE = '22023', COLUMN = 'validUntil';
    END IF;
    IF p_discount_amount IS NULL OR p_discount_amount < 0 OR p_discount_amount <> round(p_discount_amount, 2) THEN
        RAISE EXCEPTION 'The discount must be 0 or more with at most 2 decimals' USING ERRCODE = '22023', COLUMN = 'discountAmount';
    END IF;
    IF p_customer_id IS NOT NULL THEN
        SELECT c.is_active INTO v_active FROM customers c WHERE c.customer_id = p_customer_id AND c.tenant_id = p_tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Customer % not found', p_customer_id USING ERRCODE = 'P0002', COLUMN = 'customerId';
        END IF;
        IF NOT v_active THEN
            RAISE EXCEPTION 'Customer % is inactive', p_customer_id USING ERRCODE = 'NX409', COLUMN = 'customerId';
        END IF;
    END IF;
    IF p_template_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM quotation_templates t WHERE t.template_id = p_template_id AND t.tenant_id = p_tenant_id) THEN
        RAISE EXCEPTION 'Template % not found', p_template_id USING ERRCODE = 'P0002', COLUMN = 'templateId';
    END IF;
END;
$$;
