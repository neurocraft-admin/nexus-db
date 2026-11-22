-- Quotation format. Run after every release. Raises an exception naming the first thing that is missing or wrong.
-- It checks that the scripts are applied, the tables, columns, constraints and functions exist, the new reads and writes are tenant-aware, and that
-- the data holds together: every quotation's figures equal its lines, no draft holds a company snapshot, every package line has its component rows.
DO $$
DECLARE
    v_name text;
    c_tables CONSTANT text[] := ARRAY['subsidy_categories', 'subsidy_slabs', 'datasheets', 'template_datasheets', 'quotation_datasheets', 'quotation_line_components'];
    c_columns CONSTANT text[] := ARRAY[
        'items.make_text', 'quotation_templates.document_title', 'quotation_templates.hero_file_name', 'quotation_templates.capacity_kw',
        'quotation_templates.subsidy_category', 'quotation_templates.show_line_prices', 'quotation_templates.cost_notes',
        'quotation_templates.payment_terms_html', 'quotation_templates.terms_html', 'quotations.document_title', 'quotations.hero_file_name',
        'quotations.capacity_kw', 'quotations.subsidy_category', 'quotations.subsidy_amount', 'quotations.subsidy_overridden',
        'quotations.show_line_prices', 'quotations.cost_notes', 'quotations.payment_terms_html', 'quotations.terms_html',
        'quotations.extra_charges_amount', 'quotations.company_snapshot', 'quotation_template_lines.make_text', 'quotation_template_lines.is_extra_charge',
        'quotation_lines.make_text', 'quotation_lines.is_extra_charge', 'order_lines.is_extra_charge', 'orders.extra_charges_amount',
        'company_profile.bank_branch', 'company_profile.default_payment_terms_html', 'company_profile.default_terms_html', 'company_profile.default_cost_notes'];
    c_constraints CONSTANT text[] := ARRAY[
        'ck_quotations_extra_charges', 'ck_quotations_discount_payable', 'ck_quotations_subsidy_amount', 'ck_quotations_snapshot_not_draft',
        'ck_quotation_lines_extra', 'ck_quotation_template_lines_extra', 'ck_order_lines_extra', 'ck_orders_extra_charges',
        'fk_quotations_subsidy_category', 'fk_quotation_templates_subsidy_category', 'ck_subsidy_slabs_range', 'ck_subsidy_slabs_amount',
        'fk_subsidy_slabs_category', 'ck_datasheets_size', 'uq_quotation_line_components'];
    c_functions CONSTANT text[] := ARRAY[
        'fn_html_is_allowed', 'fn_suggest_subsidy', 'fn_get_subsidy_categories', 'fn_get_subsidy_slabs', 'sp_save_subsidy_slab', 'sp_check_subsidy_slab',
        'fn_get_datasheets', 'fn_get_datasheet_by_id', 'sp_save_datasheet', 'sp_check_datasheet_ids', 'sp_set_template_datasheets',
        'sp_set_quotation_datasheets', 'fn_get_template_datasheets', 'fn_get_quotation_datasheets', 'fn_company_snapshot', 'sp_check_company_defaults',
        'sp_save_company_defaults', 'sp_check_document_text', 'sp_check_document_settings', 'sp_check_line_components', 'sp_write_line_components',
        'sp_apply_subsidy', 'sp_apply_quotation_document', 'sp_apply_template_document', 'fn_template_document', 'sp_set_quotation_hero',
        'sp_set_template_hero', 'fn_get_quotation_line_components', 'fn_get_quotation_proposal', 'fn_get_quotation_company', 'fn_template_lines_json',
        'sp_copy_quotation_children'];
    c_tenant_functions CONSTANT text[] := ARRAY[
        'fn_suggest_subsidy', 'fn_get_subsidy_categories', 'fn_get_subsidy_slabs', 'sp_save_subsidy_slab', 'fn_get_datasheets', 'fn_get_datasheet_by_id',
        'sp_save_datasheet', 'sp_check_datasheet_ids', 'sp_set_template_datasheets', 'sp_set_quotation_datasheets', 'fn_get_template_datasheets',
        'fn_get_quotation_datasheets', 'fn_company_snapshot', 'sp_write_line_components', 'sp_apply_subsidy', 'sp_apply_quotation_document',
        'sp_apply_template_document', 'fn_template_document', 'sp_set_quotation_hero', 'sp_set_template_hero', 'fn_get_quotation_line_components',
        'fn_get_quotation_proposal', 'fn_get_quotation_company', 'sp_check_document_settings', 'sp_check_line_components', 'fn_template_lines_json',
        'sp_copy_quotation_children'];
BEGIN
    FOREACH v_name IN ARRAY ARRAY['29_quotation_format_schema.sql', '30_subsidy_slabs_schema.sql', '31_quotation_format_menu.sql', '32_company_quotation_defaults.sql'] LOOP
        IF NOT EXISTS (SELECT 1 FROM deployment_log d WHERE d.script_name = v_name) THEN
            RAISE EXCEPTION 'Script not applied: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_tables LOOP
        IF to_regclass('public.' || v_name) IS NULL THEN
            RAISE EXCEPTION 'Table missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_columns LOOP
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema = 'public' AND c.table_name = split_part(v_name, '.', 1) AND c.column_name = split_part(v_name, '.', 2)) THEN
            RAISE EXCEPTION 'Column missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_constraints LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conname = v_name) THEN
            RAISE EXCEPTION 'Constraint missing: %', v_name;
        END IF;
    END LOOP;
    FOREACH v_name IN ARRAY c_functions LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = v_name) THEN
            RAISE EXCEPTION 'Function missing: %', v_name;
        END IF;
    END LOOP;
    -- Every table the module adds that holds company data carries tenant_id, so callers can filter on it.
    FOREACH v_name IN ARRAY c_tables LOOP
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_name = v_name AND c.column_name = 'tenant_id') THEN
            RAISE EXCEPTION 'The table % has no tenant_id', v_name;
        END IF;
    END LOOP;
    -- Every tenant-scoped function takes p_tenant_id as its first parameter.
    SELECT string_agg(DISTINCT p.proname, ', ' ORDER BY p.proname) INTO v_name
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = ANY (c_tenant_functions)
       AND (p.proargnames IS NULL OR p.proargnames[1] <> 'p_tenant_id');
    IF v_name IS NOT NULL THEN
        RAISE EXCEPTION 'These functions do not take p_tenant_id first: %', v_name;
    END IF;
    IF NOT fn_html_is_allowed('<p>ok</p>') OR fn_html_is_allowed('<script>x</script>') OR fn_html_is_allowed('<p class="a">x</p>') THEN
        RAISE EXCEPTION 'fn_html_is_allowed does not follow its allow-list';
    END IF;
END;
$$;

-- The data holds together.
DO $$
DECLARE
    v_bad text;
BEGIN
    SELECT string_agg(q.quotation_no, ', ' ORDER BY q.quotation_no) INTO v_bad
      FROM quotations q
      LEFT JOIN LATERAL (SELECT COALESCE(sum(l.line_total), 0) AS total, COALESCE(sum(l.line_total) FILTER (WHERE l.is_extra_charge), 0) AS extra
                           FROM quotation_lines l WHERE l.quotation_id = q.quotation_id) s ON true
     WHERE q.subtotal <> s.total OR q.extra_charges_amount <> s.extra OR q.total_amount <> q.subtotal - q.discount_amount
        OR q.subsidy_amount > q.subtotal - q.extra_charges_amount - q.discount_amount;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'These quotations do not add up to their lines: %', v_bad;
    END IF;
    SELECT string_agg(q.quotation_no, ', ' ORDER BY q.quotation_no) INTO v_bad FROM quotations q WHERE q.status = 'draft' AND q.company_snapshot IS NOT NULL;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'These draft quotations hold a company snapshot: %', v_bad;
    END IF;
    SELECT string_agg(q.quotation_no, ', ' ORDER BY q.quotation_no) INTO v_bad
      FROM quotation_lines l JOIN quotations q ON q.quotation_id = l.quotation_id
     WHERE l.line_type = 'package' AND NOT EXISTS (SELECT 1 FROM quotation_line_components c WHERE c.quotation_line_id = l.quotation_line_id)
       AND EXISTS (SELECT 1 FROM package_lines pl WHERE pl.package_id = l.package_id);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'These quotations have a package line with no component rows: %', v_bad;
    END IF;
    SELECT string_agg(o.order_no, ', ' ORDER BY o.order_no) INTO v_bad
      FROM orders o WHERE o.extra_charges_amount <> (SELECT COALESCE(sum(l.line_total), 0) FROM order_lines l WHERE l.order_id = o.order_id AND l.is_extra_charge);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'These orders do not carry their extra-charge subtotal: %', v_bad;
    END IF;
    SELECT string_agg(s.category_code || ' ' || s.capacity_from_kw, ', ') INTO v_bad
      FROM subsidy_slabs a JOIN subsidy_slabs s ON s.tenant_id = a.tenant_id AND s.category_code = a.category_code AND s.slab_id <> a.slab_id AND s.is_active AND a.is_active
                                                AND s.capacity_from_kw < COALESCE(a.capacity_to_kw, 'Infinity'::numeric) AND a.capacity_from_kw < COALESCE(s.capacity_to_kw, 'Infinity'::numeric)
     WHERE a.slab_id < s.slab_id;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Active subsidy slabs overlap: %', v_bad;
    END IF;
END;
$$;
