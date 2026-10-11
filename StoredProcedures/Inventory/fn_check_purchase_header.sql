-- Validates the header of a purchase before anything is written (raises, returns nothing). Used by
-- sp_record_purchase.
--   22023 invalid parameter - empty date, or a date in the future (in the business time zone)
--   P0002 not found         - the supplier does not exist
--   NX409 rule conflict     - the supplier is inactive
CREATE OR REPLACE FUNCTION fn_check_purchase_header(p_tenant_id integer, p_supplier_id bigint, p_purchase_date date)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_active boolean;
    v_today  date := (now() AT TIME ZONE COALESCE(fn_get_setting(p_tenant_id, 'business_time_zone'), 'UTC'))::date;
BEGIN
    IF p_purchase_date IS NULL OR p_purchase_date > v_today THEN
        RAISE EXCEPTION 'The purchase date cannot be empty or in the future' USING ERRCODE = '22023';
    END IF;
    IF p_supplier_id IS NULL THEN
        RETURN;
    END IF;

    SELECT s.is_active INTO v_active FROM suppliers s
     WHERE s.supplier_id = p_supplier_id AND s.tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier % not found', p_supplier_id USING ERRCODE = 'P0002';
    END IF;
    IF NOT v_active THEN
        RAISE EXCEPTION 'The supplier is inactive' USING ERRCODE = 'NX409';
    END IF;
END;
$$;
