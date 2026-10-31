-- Module 3 (Quotations and orders). Run after every release. Raises an exception naming the first thing that is missing.
DO $$
DECLARE
    v_name text;
    c_tables CONSTANT text[] := ARRAY[
        'quotation_templates', 'quotation_template_lines', 'quotations', 'quotation_lines', 'quotation_status_log',
        'orders', 'order_lines', 'order_status_log'];
    c_functions CONSTANT text[] := ARRAY[
        'fn_business_today', 'sp_check_document_lines', 'sp_check_document_references', 'fn_normalise_document_lines',
        'sp_check_quotation_header', 'sp_save_quotation', 'sp_write_quotation', 'sp_log_quotation_status',
        'sp_log_order_status', 'sp_set_quotation_status', 'sp_expire_quotations', 'fn_create_quotation_from_template',
        'sp_duplicate_quotation', 'fn_convert_quotation_to_order', 'fn_get_order_requirements',
        'sp_check_order_stock', 'fn_get_order_shortages', 'sp_raise_order_stock_problem', 'sp_take_order_stock', 'sp_fulfil_order',
        'sp_cancel_order', 'sp_save_template', 'fn_get_templates', 'fn_get_template_by_id', 'fn_get_template_lines',
        'fn_get_quotations', 'fn_get_quotation_by_id', 'fn_get_quotation_lines', 'fn_get_quotation_revisions',
        'fn_get_lines_availability', 'fn_get_orders', 'fn_get_order_by_id', 'fn_get_order_lines'];
    c_constraints CONSTANT text[] := ARRAY[
        'uq_quotations_tenant_no', 'ck_quotations_party', 'ck_quotations_totals', 'ck_quotations_status',
        'ck_quotation_lines_total', 'uq_orders_quotation', 'uq_orders_tenant_no', 'ck_orders_fulfilled'];
BEGIN
    FOREACH v_name IN ARRAY ARRAY['14_quotations_schema.sql', '15_quotations_menu.sql', '16_quotations_settings.sql'] LOOP
        IF NOT EXISTS (SELECT 1 FROM deployment_log d WHERE d.script_name = v_name) THEN
            RAISE EXCEPTION 'Script not applied: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_tables LOOP
        IF to_regclass('public.' || v_name) IS NULL THEN
            RAISE EXCEPTION 'Table missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_functions LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = v_name) THEN
            RAISE EXCEPTION 'Function missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_constraints LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = v_name) THEN
            RAISE EXCEPTION 'Constraint missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['quotation_templates', 'quotations', 'orders'] LOOP
        IF NOT EXISTS (SELECT 1
                         FROM role_permissions rp
                         JOIN roles r ON r.role_id = rp.role_id
                         JOIN resources x ON x.resource_id = rp.resource_id
                        WHERE r.role_name = 'Admin' AND x.resource_code = v_name
                          AND rp.can_view AND rp.can_create AND rp.can_update AND rp.can_delete) THEN
            RAISE EXCEPTION 'Admin does not have full access to %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['/sales/quotations', '/sales/templates', '/sales/orders'] LOOP
        IF NOT EXISTS (SELECT 1 FROM menu_items WHERE url = v_name AND parent_id IS NOT NULL) THEN
            RAISE EXCEPTION 'Menu item missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['company_name', 'company_address', 'company_phone', 'company_bank_details',
                                  'quotation_footer_note', 'business_time_zone'] LOOP
        IF NOT EXISTS (SELECT 1 FROM app_settings WHERE setting_key = v_name) THEN
            RAISE EXCEPTION 'Setting missing: %', v_name;
        END IF;
    END LOOP;
    -- The totals on every quotation add up (the CHECK enforces it; this catches a constraint that was dropped).
    IF EXISTS (SELECT 1 FROM quotations q
                WHERE q.subtotal <> (SELECT COALESCE(sum(l.line_total), 0) FROM quotation_lines l
                                      WHERE l.quotation_id = q.quotation_id)
                  AND q.status <> 'draft') THEN
        RAISE EXCEPTION 'A quotation subtotal does not equal the sum of its lines';
    END IF;
    -- An order has exactly one quotation and a converted quotation has an order.
    IF EXISTS (SELECT 1 FROM quotations q WHERE q.status = 'converted'
                  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.quotation_id = q.quotation_id)) THEN
        RAISE EXCEPTION 'A converted quotation has no order';
    END IF;

    -- The API connects as nexus_app: it must be able to use what was just created.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_app') THEN
        FOREACH v_name IN ARRAY c_tables LOOP
            IF NOT has_table_privilege('nexus_app', 'public.' || v_name, 'SELECT,INSERT') THEN
                RAISE EXCEPTION 'nexus_app cannot use table %', v_name;
            END IF;
        END LOOP;
        FOR v_name IN SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = ANY (c_functions) LOOP
            IF NOT has_function_privilege('nexus_app', v_name, 'EXECUTE') THEN
                RAISE EXCEPTION 'nexus_app cannot execute %', v_name;
            END IF;
        END LOOP;
    END IF;
END;
$$;
