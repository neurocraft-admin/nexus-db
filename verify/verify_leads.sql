-- Module 1 (Leads). Run after every release. Raises an exception naming the first thing that is missing or wrong.
DO $$
DECLARE
    v_name text;
    c_tables CONSTANT text[] := ARRAY['lead_sources', 'lead_statuses', 'leads', 'lead_activities', 'lead_import_batches'];
    c_functions CONSTANT text[] := ARRAY[
        'fn_normalise_mobile', 'fn_try_date', 'fn_try_numeric', 'fn_get_lead_sources', 'fn_get_lead_statuses',
        'sp_save_lead_source', 'fn_get_lead_assignees', 'sp_log_lead_activity', 'sp_assert_no_open_lead_mobile',
        'sp_assert_assignee', 'sp_check_lead_fields', 'sp_insert_lead', 'fn_save_lead', 'fn_get_leads', 'fn_get_lead_by_id',
        'fn_get_lead_activities', 'fn_get_lead_source_summary', 'sp_change_lead_status', 'sp_check_lead_status_move',
        'sp_assign_lead', 'sp_add_lead_note', 'sp_set_lead_active', 'sp_find_or_create_customer', 'sp_fill_lead_quotations',
        'fn_convert_lead', 'fn_parse_import_rows', 'fn_check_import_rows', 'fn_import_leads', 'fn_import_one_lead', 'sp_assert_import_default_source',
        'fn_business_day_start', 'sp_update_lead', 'sp_check_lead_follow_up_filter', 'sp_check_quotation_lead'];
BEGIN
    FOREACH v_name IN ARRAY ARRAY['17_leads_schema.sql', '18_leads_menu.sql'] LOOP
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
    FOREACH v_name IN ARRAY ARRAY['ck_leads_mobile', 'ck_leads_converted_is_closed', 'uq_leads_tenant_no', 'fk_quotations_lead'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = v_name) THEN
            RAISE EXCEPTION 'Constraint missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY ARRAY['uq_leads_open_mobile', 'uq_leads_source_external_ref', 'uq_lead_sources_tenant_name',
                                  'ix_quotations_lead_id'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = v_name) THEN
            RAISE EXCEPTION 'Index missing: %', v_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_lead_activities_no_change') THEN
        RAISE EXCEPTION 'The lead history is not protected: trigger trg_lead_activities_no_change is missing';
    END IF;
    -- Master data: the sources and the pipeline, with a start, a Won and a Lost.
    IF (SELECT count(*) FROM lead_sources WHERE tenant_id = 1) < 5 THEN
        RAISE EXCEPTION 'The seeded lead sources are missing';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM lead_statuses WHERE tenant_id = 1 AND is_active AND is_won)
       OR NOT EXISTS (SELECT 1 FROM lead_statuses WHERE tenant_id = 1 AND is_active AND is_lost)
       OR NOT EXISTS (SELECT 1 FROM lead_statuses WHERE tenant_id = 1 AND is_active AND NOT is_won AND NOT is_lost) THEN
        RAISE EXCEPTION 'The pipeline needs an open status, a Won status and a Lost status';
    END IF;
    FOREACH v_name IN ARRAY ARRAY['leads', 'lead_sources'] LOOP
        IF NOT EXISTS (SELECT 1 FROM role_permissions rp JOIN roles r ON r.role_id = rp.role_id
                         JOIN resources x ON x.resource_id = rp.resource_id
                        WHERE r.role_name = 'Admin' AND x.resource_code = v_name
                          AND rp.can_view AND rp.can_create AND rp.can_update AND rp.can_delete) THEN
            RAISE EXCEPTION 'Admin does not have full access to %', v_name;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM menu_items WHERE url = '/sales/leads' AND parent_id IS NOT NULL) THEN
        RAISE EXCEPTION 'Menu item missing: /sales/leads';
    END IF;
    -- Consistency of the data: a lead is closed exactly when its status is Won or Lost, a converted lead is Won, every
    -- lead has its 'created' history row, and no two open leads share a mobile (the index guarantees it).
    IF EXISTS (SELECT 1 FROM leads l JOIN lead_statuses st ON st.lead_status_id = l.lead_status_id
                WHERE l.is_closed <> (st.is_won OR st.is_lost)) THEN
        RAISE EXCEPTION 'A lead''s closed flag does not match its status';
    END IF;
    IF EXISTS (SELECT 1 FROM leads l JOIN lead_statuses st ON st.lead_status_id = l.lead_status_id
                WHERE l.converted_customer_id IS NOT NULL AND NOT st.is_won) THEN
        RAISE EXCEPTION 'A converted lead is not Won';
    END IF;
    IF EXISTS (SELECT 1 FROM leads l WHERE NOT EXISTS (
                SELECT 1 FROM lead_activities a WHERE a.lead_id = l.lead_id AND a.activity_type = 'created')) THEN
        RAISE EXCEPTION 'A lead has no created history row';
    END IF;
    IF EXISTS (SELECT 1 FROM quotations q WHERE q.lead_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM leads l WHERE l.lead_id = q.lead_id)) THEN
        RAISE EXCEPTION 'A quotation points at a lead that does not exist';
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
