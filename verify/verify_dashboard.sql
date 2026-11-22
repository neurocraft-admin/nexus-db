-- Module 11 (Dashboard and reports). Run after every release. Raises an exception naming the first thing that is missing or wrong.
-- This module only READS: its views are views, its functions are STABLE (or IMMUTABLE), and no function body contains a write statement.
DO $$
DECLARE
    v_name text;
    c_views CONSTANT text[] := ARRAY['vw_business_time_zones', 'vw_lead_pipeline', 'vw_quotation_summary', 'vw_order_report', 'vw_inventory_status',
                                     'vw_stock_ledger', 'vw_ticket_summary'];
    c_functions CONSTANT text[] := ARRAY[
        'fn_business_date_of', 'fn_ticket_overdue_days', 'fn_get_period_range', 'fn_check_report_range', 'fn_resolve_report_range',
        'fn_conversion_pct', 'fn_count_leads_created', 'fn_count_leads_closed', 'fn_revenue_between', 'fn_get_customer_dues',
        'fn_get_overdue_payments', 'fn_get_conversion_buckets', 'fn_get_awaiting_reply', 'fn_get_open_lead_stages', 'fn_get_dashboard_summary', 'fn_get_revenue_by_month',
        'fn_get_lead_pipeline', 'fn_get_leads_by_source', 'fn_get_recent_quotations', 'fn_get_dashboard_low_stock', 'fn_get_dashboard_open_tickets',
        'fn_get_needs_assignment', 'fn_get_technician_workload', 'fn_get_operations_summary', 'fn_get_schedule_today', 'fn_get_sales_summary',
        'fn_get_leads_to_contact', 'fn_get_follow_ups_due', 'fn_get_expiring_quotations', 'fn_get_my_ticket_summary', 'fn_get_my_tickets',
        'fn_find_customer', 'fn_report_quotation_conversion', 'fn_report_inventory_movement', 'fn_report_ticket_resolution'];
BEGIN
    FOREACH v_name IN ARRAY ARRAY['27_dashboard_views.sql', '28_dashboard_menu.sql'] LOOP
        IF NOT EXISTS (SELECT 1 FROM deployment_log d WHERE d.script_name = v_name) THEN
            RAISE EXCEPTION 'Script not applied: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_views LOOP
        IF to_regclass('public.' || v_name) IS NULL THEN
            RAISE EXCEPTION 'View missing: %', v_name;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_name = v_name AND c.column_name = 'tenant_id') THEN
            RAISE EXCEPTION 'The view % does not expose tenant_id: callers must be able to filter on it', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_functions LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = v_name) THEN
            RAISE EXCEPTION 'Function missing: %', v_name;
        END IF;
    END LOOP;
    -- Read-only: every function of the module is STABLE or IMMUTABLE (a VOLATILE one could write), is a function and not a procedure, and no body
    -- mentions a write statement (comment lines are ignored).
    SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_name
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = ANY (c_functions) AND (p.prokind <> 'f' OR p.provolatile NOT IN ('s', 'i'));
    IF v_name IS NOT NULL THEN
        RAISE EXCEPTION 'These dashboard functions are not read-only (STABLE or IMMUTABLE functions): %', v_name;
    END IF;
    SELECT string_agg(DISTINCT p.proname, ', ' ORDER BY p.proname) INTO v_name
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = ANY (c_functions)
       AND regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g') ~ '\m(insert|update|delete|truncate|drop|alter|create|call|grant|revoke)\M';
    IF v_name IS NOT NULL THEN
        RAISE EXCEPTION 'These dashboard functions mention a write statement: %', v_name;
    END IF;
    SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_name
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname = ANY (ARRAY['dashboard', 'reports', 'report_runs', 'dashboard_cache']);
    IF v_name IS NOT NULL THEN
        RAISE EXCEPTION 'This module adds no tables, but these exist: %', v_name;
    END IF;
    FOREACH v_name IN ARRAY ARRAY['ix_leads_tenant_created', 'ix_leads_tenant_closed', 'ix_tickets_tenant_created', 'ix_quotations_tenant_created',
                                  'ix_orders_tenant_created', 'ix_orders_tenant_fulfilled', 'ix_quotation_status_log_approved',
                                  'ix_customer_credit_ledgers_charges'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = v_name) THEN
            RAISE EXCEPTION 'Index missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['ticket_overdue_days', 'credit_terms_days', 'financial_year_start_month'] LOOP
        IF NOT EXISTS (SELECT 1 FROM app_settings s WHERE s.tenant_id = 1 AND s.setting_key = v_name) THEN
            RAISE EXCEPTION 'Setting missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['dashboard', 'reports'] LOOP
        IF NOT EXISTS (SELECT 1 FROM resources WHERE resource_code = v_name) THEN
            RAISE EXCEPTION 'Resource missing: %', v_name;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM role_permissions rp JOIN roles r ON r.role_id = rp.role_id JOIN resources x ON x.resource_id = rp.resource_id
                        WHERE r.role_name = 'Admin' AND x.resource_code = v_name AND rp.can_view AND NOT rp.can_create AND NOT rp.can_update AND NOT rp.can_delete) THEN
            RAISE EXCEPTION 'Admin does not have view (only) on %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['/dashboard|chart', '/reports/quotation-conversion|receipt', '/reports/inventory-movement|layers',
                                  '/reports/ticket-resolution|wrench'] LOOP
        IF NOT EXISTS (SELECT 1 FROM menu_items WHERE url = split_part(v_name, '|', 1) AND icon = split_part(v_name, '|', 2)) THEN
            RAISE EXCEPTION 'Menu item missing: %', v_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM menu_items WHERE title = 'Reports' AND parent_id IS NULL AND url IS NULL AND icon = 'chart') THEN
        RAISE EXCEPTION 'The Reports menu group is missing';
    END IF;
    IF (SELECT count(*) FROM menu_items m JOIN menu_items g ON g.menu_item_id = m.parent_id WHERE g.title = 'Reports' AND g.parent_id IS NULL) <> 3 THEN
        RAISE EXCEPTION 'The Reports group should hold exactly three reports';
    END IF;

    -- The API connects as nexus_app: it must be able to use what was just created.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_app') THEN
        FOREACH v_name IN ARRAY c_views LOOP
            IF NOT has_table_privilege('nexus_app', 'public.' || v_name, 'SELECT') THEN
                RAISE EXCEPTION 'nexus_app cannot read %', v_name;
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
