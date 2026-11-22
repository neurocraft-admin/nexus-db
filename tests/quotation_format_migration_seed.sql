-- Quotation format migration test, step 2 of 3: legacy data written with the PREVIOUS release's functions (the database holds scripts 00-28 only, and
-- the old twelve-argument sp_save_quotation / sp_save_template). The migration check (step 3) runs after scripts 29-32 are applied on top.
-- Scratch databases only. Run by tests/quotation_format_migration.ps1; do not run it on nexus.
\set ON_ERROR_STOP on
DO $$
DECLARE
    v_user integer; v_cust bigint; v_pkg bigint; v_q bigint; v_t bigint; v_unit varchar;
    v_today date := fn_business_today(1);
BEGIN
    IF current_database() IN ('nexus', 'postgres') THEN
        RAISE EXCEPTION 'Refusing to run in the database %', current_database();
    END IF;
    INSERT INTO users (tenant_id, user_name, full_name, password_hash, role_id, user_type)
    SELECT 1, 'mig_user', 'Migration User', 'x', r.role_id, 'admin' FROM roles r WHERE r.tenant_id = 1 AND r.role_name = 'Admin' RETURNING user_id INTO v_user;
    SELECT unit_code INTO v_unit FROM units WHERE tenant_id = 1 ORDER BY unit_code LIMIT 1;
    INSERT INTO customers (tenant_id, customer_name, mobile) VALUES (1, 'MIG Customer', '7099999931') RETURNING customer_id INTO v_cust;
    INSERT INTO items (tenant_id, item_code, item_name, unit, selling_price) VALUES (1, 'MIGPANEL', 'MIG panel', v_unit, 100), (1, 'MIGINV', 'MIG inverter', v_unit, 500);
    INSERT INTO packages (tenant_id, package_code, package_name, package_price) VALUES (1, 'MIGKIT', 'MIG kit', 1000) RETURNING package_id INTO v_pkg;
    INSERT INTO package_lines (tenant_id, package_id, item_id, quantity, sort_order)
    SELECT 1, v_pkg, i.item_id, CASE i.item_code WHEN 'MIGPANEL' THEN 4 ELSE 1 END, CASE i.item_code WHEN 'MIGPANEL' THEN 1 ELSE 2 END FROM items i WHERE i.item_code LIKE 'MIG%' AND i.tenant_id = 1;
    -- A quotation with multi-line terms (including characters that must be escaped) and a package line, written by the old path.
    CALL sp_save_quotation(1, NULL, v_cust, NULL, NULL, v_today, v_today + 30, 0, E'Payment within 7 days.\r\n\r\nWarranty < 5 years & parts > labour\nThank you', 'legacy',
                           v_user, jsonb_build_array(jsonb_build_object('lineType', 'package', 'packageId', v_pkg, 'quantity', 2),
                                                     jsonb_build_object('lineType', 'custom', 'description', 'Installation', 'quantity', 1, 'unitPrice', 250)), v_q);
    CALL sp_save_template(1, NULL, 'MIG template', NULL, 30, E'Line A\nLine B', true,
                          jsonb_build_array(jsonb_build_object('lineType', 'package', 'packageId', v_pkg, 'quantity', 1)), v_t);
    INSERT INTO company_profile (tenant_id, display_name, quotation_terms, other_payment_details)
    VALUES (1, 'Migration Solar', E'Company term one\nCompany term <two>', 'HDFC A/c 1234567890 (old free text)')
    ON CONFLICT (tenant_id) DO UPDATE SET display_name = EXCLUDED.display_name, quotation_terms = EXCLUDED.quotation_terms, other_payment_details = EXCLUDED.other_payment_details;
    -- Send it, so a sent quotation with no snapshot exists too (sent before snapshots existed).
    CALL sp_set_quotation_status(1, v_q, 'sent', v_user, NULL);
END;
$$;
SELECT 'legacy data written' AS step;
