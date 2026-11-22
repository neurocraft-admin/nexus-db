-- Quotation format migration test, step 3 of 3: what scripts 29-32 did to the legacy rows written by tests/quotation_format_migration_seed.sql.
-- Raises an exception naming the first thing that is wrong. Scratch databases only. Run twice by tests/quotation_format_migration.ps1 (after the first
-- apply and after a second apply), because the migrations must change nothing the second time.
\set ON_ERROR_STOP on
DO $$
DECLARE
    r record;
BEGIN
    SELECT q.terms_html, q.terms_text, q.show_line_prices, q.subsidy_category, q.subsidy_amount, q.extra_charges_amount, q.company_snapshot, q.status INTO r
      FROM quotations q WHERE q.notes = 'legacy' AND q.tenant_id = 1;
    IF r.terms_html IS DISTINCT FROM '<p>Payment within 7 days.</p><p>Warranty &lt; 5 years &amp; parts &gt; labour</p><p>Thank you</p>' THEN
        RAISE EXCEPTION 'Legacy terms were not converted to paragraphs: %', r.terms_html;
    END IF;
    IF r.terms_text IS NULL THEN
        RAISE EXCEPTION 'The old terms_text was removed; it must stay in place';
    END IF;
    IF NOT r.show_line_prices OR r.subsidy_category <> 'none' OR r.subsidy_amount <> 0 OR r.extra_charges_amount <> 0 THEN
        RAISE EXCEPTION 'A legacy quotation did not get the defaults (prices shown, no subsidy, no extra charges)';
    END IF;
    IF r.status <> 'sent' OR r.company_snapshot IS NOT NULL THEN
        RAISE EXCEPTION 'A quotation sent before snapshots existed must stay sent with no snapshot (it reads the live profile)';
    END IF;
    IF (SELECT count(*) FROM quotation_line_components c JOIN quotation_lines l ON l.quotation_line_id = c.quotation_line_id
         JOIN quotations q ON q.quotation_id = l.quotation_id WHERE q.notes = 'legacy') <> 2 THEN
        RAISE EXCEPTION 'The legacy package line did not get its two component rows';
    END IF;
    IF (SELECT string_agg(c.description || ' ' || c.quantity::text, ', ' ORDER BY c.sort_order) FROM quotation_line_components c
         JOIN quotation_lines l ON l.quotation_line_id = c.quotation_line_id JOIN quotations q ON q.quotation_id = l.quotation_id WHERE q.notes = 'legacy')
       <> 'MIG panel 4.000, MIG inverter 1.000' THEN
        RAISE EXCEPTION 'The legacy component rows are wrong';
    END IF;
    IF (SELECT t.terms_html FROM quotation_templates t WHERE t.template_name = 'MIG template') <> '<p>Line A</p><p>Line B</p>' THEN
        RAISE EXCEPTION 'The legacy template terms were not converted';
    END IF;
    IF (SELECT c.default_terms_html FROM company_profile c WHERE c.tenant_id = 1) <> '<p>Company term one</p><p>Company term &lt;two&gt;</p>' THEN
        RAISE EXCEPTION 'The company quotation_terms were not converted to default_terms_html';
    END IF;
    IF (SELECT c.other_payment_details FROM company_profile c WHERE c.tenant_id = 1) <> 'HDFC A/c 1234567890 (old free text)' OR (SELECT c.bank_branch FROM company_profile c WHERE c.tenant_id = 1) IS NOT NULL THEN
        RAISE EXCEPTION 'other_payment_details must be left exactly as it was and the new branch field empty';
    END IF;
    IF (SELECT count(*) FROM subsidy_categories WHERE tenant_id = 1) <> 3 OR EXISTS (SELECT 1 FROM subsidy_slabs) THEN
        RAISE EXCEPTION 'Three subsidy categories and no slabs were expected';
    END IF;
    IF (SELECT count(*) FROM deployment_log WHERE script_name IN ('29_quotation_format_schema.sql', '30_subsidy_slabs_schema.sql', '31_quotation_format_menu.sql', '32_company_quotation_defaults.sql')) <> 4 THEN
        RAISE EXCEPTION 'The four scripts are not all recorded in deployment_log';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM fn_get_quotation_proposal(1, (SELECT q.quotation_id FROM quotations q WHERE q.notes = 'legacy'))) THEN
        RAISE EXCEPTION 'The proposal of the legacy quotation is empty';
    END IF;
END;
$$;
SELECT 'migration check passed' AS result;
