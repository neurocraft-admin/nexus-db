-- Quotation format: behaviour tests for the database, one rolled-back transaction, safe on any database that has scripts 00-32 and the function
-- files applied (an empty one or one with real data). Nothing it writes survives.
--   docker exec -i nexus-pg-test psql -U postgres -d <db> -v ON_ERROR_STOP=1 < tests/test_quotation_format.sql
-- The test data is all its own (QF-prefixed codes, one test user and customer); the slab table is emptied for the test (inside the transaction) so a
-- real slab cannot change what is measured. Every figure is hand-calculated in the comments.
\set ON_ERROR_STOP on
SET client_min_messages = warning;
BEGIN;

CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v bigint);
CREATE TEMP TABLE t_pass (label text);
CREATE FUNCTION pg_temp.ctx(p_key text) RETURNS bigint LANGUAGE sql AS $$ SELECT v FROM t_ctx WHERE k = p_key $$;
CREATE FUNCTION pg_temp.setctx(p_key text, p_val bigint) RETURNS void LANGUAGE sql AS
    $$ INSERT INTO t_ctx VALUES (p_key, p_val) ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v $$;
CREATE FUNCTION pg_temp.ok(p_label text, p_cond boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN
        RAISE EXCEPTION 'FAILED: %', p_label;
    END IF;
    INSERT INTO t_pass VALUES (p_label);
END;
$$;
CREATE FUNCTION pg_temp.fails(p_label text, p_sql text, p_state text, p_column text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_state text; v_column text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE;
        GET STACKED DIAGNOSTICS v_column = COLUMN_NAME;
    END;
    PERFORM pg_temp.ok(p_label || ' [refused with ' || p_state || ', got ' || COALESCE(v_state, 'no error') || ']', v_state = p_state);
    IF p_column IS NOT NULL THEN
        PERFORM pg_temp.ok(p_label || ' [names column ' || p_column || ']', v_column = p_column);
    END IF;
END;
$$;
-- Saves a quotation for the test customer and returns its id. p_lines and p_document are JSON text; p_id NULL creates a new one.
CREATE FUNCTION pg_temp.save_q(p_id bigint, p_discount numeric, p_lines text, p_document text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    v_id bigint;
    v_today date := fn_business_today(1);
BEGIN
    CALL sp_save_quotation(1, p_id, pg_temp.ctx('cust')::bigint, NULL, NULL, v_today, v_today + 30, p_discount, NULL, NULL, pg_temp.ctx('user')::integer,
                           p_lines::jsonb, v_id, p_document::jsonb);
    RETURN v_id;
END;
$$;

-- ---- fixtures ----------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_role integer; v_user integer; v_cust bigint; v_pkg bigint; v_unit varchar;
BEGIN
    SELECT r.role_id INTO v_role FROM roles r WHERE r.tenant_id = 1 AND r.role_name = 'Admin';
    INSERT INTO users (tenant_id, user_name, full_name, password_hash, role_id, user_type) VALUES (1, 'qf_user', 'QF User', 'x', v_role, 'admin') RETURNING user_id INTO v_user;
    PERFORM pg_temp.setctx('user', v_user);
    SELECT unit_code INTO v_unit FROM units WHERE tenant_id = 1 ORDER BY unit_code LIMIT 1;
    INSERT INTO customers (tenant_id, customer_name, mobile, address) VALUES (1, 'QF Customer', '7099999901', 'Naruvamoodu, Trivandrum') RETURNING customer_id INTO v_cust;
    PERFORM pg_temp.setctx('cust', v_cust);
    INSERT INTO items (tenant_id, item_code, item_name, unit, selling_price, make_text) VALUES (1, 'QFPANEL', 'QF Solar panel', v_unit, 17500, 'ADANI Warranty 30 years');
    INSERT INTO items (tenant_id, item_code, item_name, unit, selling_price, make_text) VALUES (1, 'QFINV', 'QF Micro inverter', v_unit, 60000, 'DEYE Warranty 10 Years');
    INSERT INTO items (tenant_id, item_code, item_name, unit, selling_price) VALUES (1, 'QFPLAIN', 'QF Plain item', v_unit, 100);
    PERFORM pg_temp.setctx('panel', (SELECT item_id FROM items WHERE item_code = 'QFPANEL' AND tenant_id = 1));
    PERFORM pg_temp.setctx('inv', (SELECT item_id FROM items WHERE item_code = 'QFINV' AND tenant_id = 1));
    PERFORM pg_temp.setctx('plain', (SELECT item_id FROM items WHERE item_code = 'QFPLAIN' AND tenant_id = 1));
    -- A package: 10 panels and 3 inverters per set, priced at 150,000 per set.
    INSERT INTO packages (tenant_id, package_code, package_name, package_price) VALUES (1, 'QFPKG', 'QF 6 kW kit', 150000) RETURNING package_id INTO v_pkg;
    INSERT INTO package_lines (tenant_id, package_id, item_id, quantity, sort_order) VALUES (1, v_pkg, pg_temp.ctx('panel'), 10, 1), (1, v_pkg, pg_temp.ctx('inv'), 3, 2);
    PERFORM pg_temp.setctx('pkg', v_pkg);
    DELETE FROM subsidy_slabs WHERE tenant_id = 1;   -- rolled back; real slabs must not affect the measurements
END;
$$;

-- ---- subsidy slabs -----------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_id bigint;
BEGIN
    CALL sp_save_subsidy_slab(1, NULL, 'domestic', 1, 2, 30000, true, pg_temp.ctx('user')::integer, v_id);   -- [1, 2) kW
    CALL sp_save_subsidy_slab(1, NULL, 'domestic', 2, 3, 60000, true, pg_temp.ctx('user')::integer, v_id);   -- [2, 3) kW
    CALL sp_save_subsidy_slab(1, NULL, 'domestic', 3, NULL, 78000, true, pg_temp.ctx('user')::integer, v_id); -- 3 kW and above
    PERFORM pg_temp.setctx('slab_open', v_id);
    PERFORM pg_temp.ok('three slabs saved', (SELECT count(*) FROM fn_get_subsidy_slabs(1, false)) = 3);
    PERFORM pg_temp.ok('the lower bound is included, the upper is not: 1.00 and 1.99 give 30,000, 2.00 gives 60,000',
        fn_suggest_subsidy(1, 'domestic', 1) = 30000 AND fn_suggest_subsidy(1, 'domestic', 1.99) = 30000 AND fn_suggest_subsidy(1, 'domestic', 2) = 60000);
    PERFORM pg_temp.ok('2.5 gives 60,000; 3 and 50 give 78,000 (no upper bound)',
        fn_suggest_subsidy(1, 'domestic', 2.5) = 60000 AND fn_suggest_subsidy(1, 'domestic', 3) = 78000 AND fn_suggest_subsidy(1, 'domestic', 50) = 78000);
    PERFORM pg_temp.ok('below the first slab, an unknown capacity and a category without subsidy suggest nothing',
        fn_suggest_subsidy(1, 'domestic', 0.5) IS NULL AND fn_suggest_subsidy(1, 'domestic', NULL) IS NULL
        AND fn_suggest_subsidy(1, 'commercial', 6) IS NULL AND fn_suggest_subsidy(1, 'none', 6) IS NULL);
    CALL sp_save_subsidy_slab(1, NULL, 'domestic', 0.5, 1, 15000, true, pg_temp.ctx('user')::integer, v_id);   -- fractional bounds
    PERFORM pg_temp.ok('a fractional bound works: 0.75 kW gives 15,000', fn_suggest_subsidy(1, 'domestic', 0.75) = 15000);
    PERFORM pg_temp.ok('slabs are listed by capacity', (SELECT string_agg(s.capacity_from_kw::text, ',' ORDER BY ord) FROM
        (SELECT capacity_from_kw, row_number() OVER () AS ord FROM fn_get_subsidy_slabs(1, false)) s) = '0.50,1.00,2.00,3.00');
END;
$$;
SELECT pg_temp.fails('a range that overlaps an active slab is refused', $q$CALL sp_save_subsidy_slab(1, NULL, 'domestic', 2.5, 4, 1, true, 1, NULL)$q$, 'NX409', 'capacityFromKw');
SELECT pg_temp.fails('a second open-ended slab is refused', $q$CALL sp_save_subsidy_slab(1, NULL, 'domestic', 5, NULL, 1, true, 1, NULL)$q$, 'NX409', 'capacityFromKw');
SELECT pg_temp.fails('the same start as an active slab is refused', $q$CALL sp_save_subsidy_slab(1, NULL, 'domestic', 1, 1.5, 1, true, 1, NULL)$q$, 'NX409', 'capacityFromKw');
SELECT pg_temp.fails('a category without subsidy has no slabs', $q$CALL sp_save_subsidy_slab(1, NULL, 'commercial', 1, 2, 1, true, 1, NULL)$q$, '22023', 'categoryCode');
SELECT pg_temp.fails('an unknown category is not found', $q$CALL sp_save_subsidy_slab(1, NULL, 'nope', 1, 2, 1, true, 1, NULL)$q$, 'P0002', 'categoryCode');
SELECT pg_temp.fails('an upper bound not above the lower one is refused', $q$CALL sp_save_subsidy_slab(1, NULL, 'domestic', 7, 7, 1, true, 1, NULL)$q$, '22023', 'capacityToKw');
SELECT pg_temp.fails('a negative lower bound is refused', $q$CALL sp_save_subsidy_slab(1, NULL, 'domestic', -1, 0.4, 1, true, 1, NULL)$q$, '22023', 'capacityFromKw');
SELECT pg_temp.fails('an amount with three decimals is refused', $q$CALL sp_save_subsidy_slab(1, NULL, 'domestic', 9, 10, 1.005, true, 1, NULL)$q$, '22023', 'amount');
SELECT pg_temp.fails('a negative amount is refused', $q$CALL sp_save_subsidy_slab(1, NULL, 'domestic', 9, 10, -1, true, 1, NULL)$q$, '22023', 'amount');
SELECT pg_temp.fails('an unknown slab is not found', $q$CALL sp_save_subsidy_slab(1, 999999999, 'domestic', 9, 10, 1, true, 1, NULL)$q$, 'P0002');
DO $$
DECLARE
    v_id bigint;
BEGIN
    CALL sp_save_subsidy_slab(1, pg_temp.ctx('slab_open'), 'domestic', 3, NULL, 80000, true, pg_temp.ctx('user')::integer, v_id);
    PERFORM pg_temp.ok('changing a slab to the same range does not clash with itself', fn_suggest_subsidy(1, 'domestic', 6) = 80000);
    CALL sp_save_subsidy_slab(1, pg_temp.ctx('slab_open'), 'domestic', 3, NULL, 78000, false, pg_temp.ctx('user')::integer, v_id);
    PERFORM pg_temp.ok('a switched-off slab suggests nothing and is hidden from the default list',
        fn_suggest_subsidy(1, 'domestic', 6) IS NULL AND (SELECT count(*) FROM fn_get_subsidy_slabs(1, false)) = 3 AND (SELECT count(*) FROM fn_get_subsidy_slabs(1, true)) = 4);
    CALL sp_save_subsidy_slab(1, NULL, 'domestic', 3, 10, 70000, true, pg_temp.ctx('user')::integer, v_id);   -- the freed range can be reused
    CALL sp_save_subsidy_slab(1, NULL, 'domestic', 10, NULL, 99000, true, pg_temp.ctx('user')::integer, v_id);
    PERFORM pg_temp.ok('the freed range is reused: 6 kW gives 70,000 and 12 kW gives 99,000', fn_suggest_subsidy(1, 'domestic', 6) = 70000 AND fn_suggest_subsidy(1, 'domestic', 12) = 99000);
END;
$$;
SELECT pg_temp.fails('switching a slab back on is refused while its range is taken', $q$CALL sp_save_subsidy_slab(1, pg_temp.ctx('slab_open')::bigint, 'domestic', 3, NULL, 78000, true, 1, NULL)$q$, 'NX409', 'capacityFromKw');
DO $$
BEGIN
    -- Put the slabs back as the rest of the test expects: 3 kW and above = 78,000; 1-2 = 30,000; 2-3 = 60,000.
    UPDATE subsidy_slabs SET is_active = false WHERE tenant_id = 1 AND capacity_from_kw IN (3, 10) AND capacity_to_kw IS NOT NULL;
    UPDATE subsidy_slabs SET is_active = false WHERE tenant_id = 1 AND capacity_from_kw = 10;
    UPDATE subsidy_slabs SET is_active = true, amount = 78000 WHERE slab_id = pg_temp.ctx('slab_open');
    PERFORM pg_temp.ok('the slabs are back to 3 kW and above = 78,000', fn_suggest_subsidy(1, 'domestic', 6) = 78000);
    PERFORM pg_temp.ok('tenant 2 sees none of tenant 1''s slabs', NOT EXISTS (SELECT 1 FROM fn_get_subsidy_slabs(2, true)) AND fn_suggest_subsidy(2, 'domestic', 6) IS NULL);
    PERFORM pg_temp.ok('three categories are listed in order', (SELECT string_agg(category_code, ',') FROM fn_get_subsidy_categories(1)) = 'none,domestic,commercial');
END;
$$;

-- ---- the restricted HTML -------------------------------------------------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.ok('allowed tags pass', fn_html_is_allowed('<h2>Payment terms</h2><p>Pay <strong>70%</strong> and <em>30%</em><br/>later</p><ul><li>one</li></ul><ol><li>two</li></ol>'));
    PERFORM pg_temp.ok('escaped angle brackets and ampersands pass', fn_html_is_allowed('<p>1 &lt; 2 &amp; 3 &gt; 2</p>'));
    PERFORM pg_temp.ok('NULL and empty pass', fn_html_is_allowed(NULL) AND fn_html_is_allowed(''));
    PERFORM pg_temp.ok('a script tag is refused', NOT fn_html_is_allowed('<p>x</p><script>alert(1)</script>'));
    PERFORM pg_temp.ok('an attribute is refused', NOT fn_html_is_allowed('<p onclick="x()">x</p>') AND NOT fn_html_is_allowed('<p class="a">x</p>'));
    PERFORM pg_temp.ok('a link, an image and a style are refused', NOT fn_html_is_allowed('<a href="http://x">x</a>') AND NOT fn_html_is_allowed('<img src=x>') AND NOT fn_html_is_allowed('<style>p{}</style>'));
    PERFORM pg_temp.ok('a bare angle bracket is refused', NOT fn_html_is_allowed('<p>1 < 2</p>') AND NOT fn_html_is_allowed('<p>1 > 2</p>') AND NOT fn_html_is_allowed('<p'));
    PERFORM pg_temp.ok('tag names are case-insensitive', fn_html_is_allowed('<P><STRONG>x</STRONG></P>'));
END;
$$;

-- ---- datasheets ----------------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_id bigint;
BEGIN
    CALL sp_save_datasheet(1, NULL, 'Panel datasheet', true, 'qf-aaaa.pdf', 'panel.pdf', 1000, pg_temp.ctx('user')::integer, v_id); PERFORM pg_temp.setctx('ds1', v_id);
    CALL sp_save_datasheet(1, NULL, 'Inverter datasheet', true, 'qf-bbbb.pdf', 'inverter.pdf', 2000, pg_temp.ctx('user')::integer, v_id); PERFORM pg_temp.setctx('ds2', v_id);
    CALL sp_save_datasheet(1, NULL, 'Old datasheet', false, 'qf-cccc.pdf', 'old.pdf', 3000, pg_temp.ctx('user')::integer, v_id); PERFORM pg_temp.setctx('ds3', v_id);
    PERFORM pg_temp.ok('the library lists the active datasheets by name', (SELECT string_agg(datasheet_name, ',') FROM fn_get_datasheets(1, false) WHERE stored_file_name LIKE 'qf-%') = 'Inverter datasheet,Panel datasheet');
    PERFORM pg_temp.ok('inactive ones are listed on request', (SELECT count(*) FROM fn_get_datasheets(1, true) WHERE stored_file_name LIKE 'qf-%') = 3);
    CALL sp_save_datasheet(1, pg_temp.ctx('ds1'), 'Panel datasheet (TOPCon)', true, NULL, NULL, NULL, pg_temp.ctx('user')::integer, v_id);
    PERFORM pg_temp.ok('a datasheet can be renamed; its file does not change', (SELECT datasheet_name || '/' || stored_file_name FROM fn_get_datasheet_by_id(1, pg_temp.ctx('ds1')))
                       = 'Panel datasheet (TOPCon)/qf-aaaa.pdf');
    CALL sp_save_datasheet(1, pg_temp.ctx('ds1'), 'Panel datasheet', true, NULL, NULL, NULL, pg_temp.ctx('user')::integer, v_id);
END;
$$;
SELECT pg_temp.fails('an active datasheet with the same name is refused whatever the capitals', $q$CALL sp_save_datasheet(1, NULL, 'PANEL DATASHEET', true, 'qf-dddd.pdf', 'p.pdf', 10, 1, NULL)$q$, 'NX409', 'datasheetName');
SELECT pg_temp.fails('a new datasheet needs its file', $q$CALL sp_save_datasheet(1, NULL, 'No file', true, NULL, NULL, NULL, 1, NULL)$q$, '22023', 'file');
SELECT pg_temp.fails('a name is needed', $q$CALL sp_save_datasheet(1, NULL, '   ', true, 'qf-eeee.pdf', 'p.pdf', 10, 1, NULL)$q$, '22023', 'datasheetName');
SELECT pg_temp.fails('an unknown datasheet is not found', $q$CALL sp_save_datasheet(1, 999999999, 'x', true, NULL, NULL, NULL, 1, NULL)$q$, 'P0002');

-- ---- a quotation with the whole document -------------------------------------------------------------------------------------------------
-- Lines: 10 panels at 17,500 = 175,000; 3 inverters at 60,000 = 180,000; KSEB feasibility 1,000 and grid registration 6,180 (extra charges).
-- subtotal 362,180; extra 7,180; customer payable 355,000; 6 kW domestic = 78,000 (the 3 kW and above slab); after subsidy 277,000; total 362,180.
DO $$
DECLARE
    v_q bigint;
    r record;
    v_lines text := '[{"lineType":"item","itemId":' || pg_temp.ctx('panel') || ',"quantity":10},{"lineType":"item","itemId":' || pg_temp.ctx('inv') || ',"quantity":3},'
        || '{"lineType":"custom","description":"KSEB feasibility","quantity":1,"unitPrice":1000,"isExtraCharge":true,"makeText":"Feasibility - 1,000/-"},'
        || '{"lineType":"custom","description":"KSEB grid registration","quantity":1,"unitPrice":6180,"isExtraCharge":true}]';
    v_doc text := '{"documentTitle":"Quotation for {capacity} on grid","capacityKw":6,"subsidyCategory":"domestic","showLinePrices":false,"costNotes":"*KSEB charges extra",'
        || '"paymentTermsHtml":"<p>70% before dispatch</p>","termsHtml":"<ul><li>Valid for 30 days</li></ul>","datasheetIds":[' || pg_temp.ctx('ds2') || ',' || pg_temp.ctx('ds1') || ']}';
BEGIN
    v_q := pg_temp.save_q(NULL, 0, v_lines, v_doc);
    PERFORM pg_temp.setctx('q1', v_q);
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_q);
    PERFORM pg_temp.ok('subtotal 362,180, extra charges 7,180, total 362,180', r.subtotal = 362180 AND r.extra_charges_amount = 7180 AND r.total_amount = 362180);
    PERFORM pg_temp.ok('customer payable 355,000, subsidy 78,000 (from the slabs, not typed), after subsidy 277,000',
        r.customer_payable = 355000 AND r.subsidy_amount = 78000 AND r.subsidy_overridden = false AND r.suggested_subsidy = 78000 AND r.after_subsidy = 277000);
    PERFORM pg_temp.ok('the document settings are saved', r.document_title = 'Quotation for {capacity} on grid' AND r.capacity_kw = 6 AND r.subsidy_category = 'domestic'
        AND r.subsidy_category_name = 'Domestic' AND r.show_line_prices = false AND r.cost_notes = '*KSEB charges extra'
        AND r.payment_terms_html = '<p>70% before dispatch</p>' AND r.terms_html = '<ul><li>Valid for 30 days</li></ul>');
    PERFORM pg_temp.ok('the customer address is returned; a draft has no company snapshot', r.customer_address = 'Naruvamoodu, Trivandrum' AND r.has_company_snapshot = false);
    PERFORM pg_temp.ok('the datasheets keep the order they were chosen in', (SELECT string_agg(datasheet_name, ',' ORDER BY sort_order) FROM fn_get_quotation_datasheets(1, v_q)) = 'Inverter datasheet,Panel datasheet');
    PERFORM pg_temp.ok('an item line takes the item''s make text; a custom line keeps the one given; one with none has none',
        (SELECT string_agg(coalesce(make_text, '-'), '|' ORDER BY sort_order) FROM fn_get_quotation_lines(1, v_q)) = 'ADANI Warranty 30 years|DEYE Warranty 10 Years|Feasibility - 1,000/-|-');
    PERFORM pg_temp.ok('the extra-charge flags are saved on the right lines', (SELECT string_agg(is_extra_charge::text, ',' ORDER BY sort_order) FROM fn_get_quotation_lines(1, v_q)) = 'false,false,true,true');
    PERFORM pg_temp.ok('the proposal lists all four lines', (SELECT count(*) FROM fn_get_quotation_proposal(1, v_q)) = 4);
END;
$$;

-- ---- subsidy rules and the discount ---------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_q bigint := pg_temp.ctx('q1');
    v_lines text := '[{"lineType":"item","itemId":' || pg_temp.ctx('panel') || ',"quantity":10},{"lineType":"item","itemId":' || pg_temp.ctx('inv') || ',"quantity":3},'
        || '{"lineType":"custom","description":"KSEB fees","quantity":1,"unitPrice":7180,"isExtraCharge":true}]';
    r record;
BEGIN
    PERFORM pg_temp.save_q(v_q, 5000, v_lines, NULL);
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_q);
    PERFORM pg_temp.ok('an edit with no document settings keeps them all (title, texts, datasheets, subsidy) and recalculates the figures',
        r.document_title IS NOT NULL AND r.terms_html IS NOT NULL AND r.subsidy_amount = 78000 AND r.customer_payable = 350000 AND r.after_subsidy = 272000
        AND (SELECT count(*) FROM fn_get_quotation_datasheets(1, v_q)) = 2);
    PERFORM pg_temp.save_q(v_q, 5000, v_lines, '{"subsidyAmount":50000}');
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_q);
    PERFORM pg_temp.ok('a typed amount different from the slabs is an override', r.subsidy_amount = 50000 AND r.subsidy_overridden = true AND r.after_subsidy = 300000);
    PERFORM pg_temp.save_q(v_q, 5000, v_lines, '{"documentTitle":"Changed"}');
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_q);
    PERFORM pg_temp.ok('an override stays when the document says nothing about the subsidy', r.subsidy_amount = 50000 AND r.subsidy_overridden = true AND r.document_title = 'Changed');
    PERFORM pg_temp.save_q(v_q, 5000, v_lines, '{"subsidyAmount":78000}');
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_q);
    PERFORM pg_temp.ok('typing exactly the suggested amount is not an override', r.subsidy_amount = 78000 AND r.subsidy_overridden = false);
    PERFORM pg_temp.save_q(v_q, 5000, v_lines, '{"subsidyAmount":50000}');
    PERFORM pg_temp.save_q(v_q, 5000, v_lines, '{"subsidyAmount":null}');
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_q);
    PERFORM pg_temp.ok('a null amount drops the override and follows the slabs again', r.subsidy_amount = 78000 AND r.subsidy_overridden = false);
    PERFORM pg_temp.save_q(v_q, 5000, v_lines, '{"capacityKw":2.5}');
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_q);
    PERFORM pg_temp.ok('changing the capacity follows the slabs: 2.5 kW gives 60,000', r.capacity_kw = 2.5 AND r.subsidy_amount = 60000);
    PERFORM pg_temp.save_q(v_q, 5000, v_lines, '{"capacityKw":6,"subsidyCategory":"commercial"}');
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_q);
    PERFORM pg_temp.ok('a commercial quotation has no subsidy', r.subsidy_category = 'commercial' AND r.subsidy_amount = 0 AND r.after_subsidy = r.customer_payable);
    PERFORM pg_temp.save_q(v_q, 5000, v_lines, '{"subsidyCategory":"domestic"}');
    PERFORM pg_temp.save_q(v_q, 300000, v_lines, NULL);
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_q);
    PERFORM pg_temp.ok('a discount that leaves less payable than the suggested subsidy caps the suggestion at the payable (55,000), after subsidy 0',
        r.customer_payable = 55000 AND r.subsidy_amount = 55000 AND r.after_subsidy = 0);
    PERFORM pg_temp.save_q(v_q, 0, v_lines, '{"subsidyAmount":null}');
END;
$$;
SELECT pg_temp.fails('a typed subsidy above the customer payable is refused', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":1000}]', '{"subsidyAmount":1001}')$q$, pg_temp.ctx('q1')), '22023', 'subsidyAmount');
SELECT pg_temp.fails('a negative subsidy is refused', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":1000}]', '{"subsidyAmount":-1}')$q$, pg_temp.ctx('q1')), '22023', 'subsidyAmount');
SELECT pg_temp.fails('a discount above the payable is refused, extra charges cannot be discounted', format($q$SELECT pg_temp.save_q(%s, 356000, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":355000},{"lineType":"custom","description":"KSEB","quantity":1,"unitPrice":7180,"isExtraCharge":true}]', NULL)$q$, pg_temp.ctx('q1')), '22023', 'discountAmount');
SELECT pg_temp.fails('an extra charge can only be a custom line', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"item","itemId":%s,"quantity":1,"isExtraCharge":true}]', NULL)$q$, pg_temp.ctx('q1'), pg_temp.ctx('panel')), '22023', 'lines');
SELECT pg_temp.fails('an unknown subsidy category is not found', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":10}]', '{"subsidyCategory":"nope"}')$q$, pg_temp.ctx('q1')), 'P0002', 'subsidyCategory');
SELECT pg_temp.fails('a capacity of 0 is refused', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":10}]', '{"capacityKw":0}')$q$, pg_temp.ctx('q1')), '22023', 'capacityKw');
SELECT pg_temp.fails('a title over 250 characters is refused', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":10}]', %L)$q$, pg_temp.ctx('q1'), '{"documentTitle":"' || repeat('x', 251) || '"}'), '22023', 'documentTitle');
SELECT pg_temp.fails('terms with a script tag are refused', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":10}]', %L)$q$, pg_temp.ctx('q1'), '{"termsHtml":"<p>x</p><script>alert(1)</script>"}'), '22023', 'termsHtml');
SELECT pg_temp.fails('payment terms with an attribute are refused', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":10}]', %L)$q$, pg_temp.ctx('q1'), '{"paymentTermsHtml":"<p style=\"x\">x</p>"}'), '22023', 'paymentTermsHtml');
SELECT pg_temp.fails('terms over 20,000 characters are refused', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":10}]', %L)$q$, pg_temp.ctx('q1'), '{"termsHtml":"<p>' || repeat('x', 20001) || '</p>"}'), '22023', 'termsHtml');
SELECT pg_temp.fails('showLinePrices must be true or false', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":10}]', '{"showLinePrices":"yes"}')$q$, pg_temp.ctx('q1')), '22023', 'showLinePrices');
DO $$
DECLARE
    r record;
BEGIN
    SELECT * INTO r FROM fn_get_quotation_by_id(1, pg_temp.ctx('q1'));
    PERFORM pg_temp.ok('a refused save changes nothing', r.subsidy_amount = 78000 AND r.customer_payable = 355000 AND r.document_title = 'Changed');
    PERFORM pg_temp.ok('the old twelve-argument save still works (a caller that does not pass the document)',
        (SELECT pg_temp.save_q(NULL, 0, '[{"lineType":"custom","description":"Old path","quantity":2,"unitPrice":50.25}]', NULL)) IS NOT NULL);
    PERFORM pg_temp.ok('a quotation saved without settings has the defaults: prices shown, no subsidy, no extra charges',
        (SELECT show_line_prices AND subsidy_category = 'none' AND subsidy_amount = 0 AND extra_charges_amount = 0 AND capacity_kw IS NULL
           FROM fn_get_quotation_by_id(1, (SELECT max(quotation_id) FROM quotations WHERE notes IS NULL AND created_by = pg_temp.ctx('user')::integer))));
END;
$$;

-- ---- a package printed as its components ------------------------------------------------------------------------------------------------------
-- 2 sets of the package: components 10 panels and 3 inverters per set -> 20 panels and 6 inverters on the proposal; the package price (2 x 150,000) is not a row of components.
DO $$
DECLARE
    v_q bigint;
    v_lines text := '[{"lineType":"package","packageId":' || pg_temp.ctx('pkg') || ',"quantity":2},{"lineType":"item","itemId":' || pg_temp.ctx('plain') || ',"quantity":4}]';
BEGIN
    v_q := pg_temp.save_q(NULL, 0, v_lines, NULL);
    PERFORM pg_temp.setctx('q2', v_q);
    PERFORM pg_temp.ok('the package''s components are copied onto the quotation',
        (SELECT string_agg(item_code || ' ' || quantity::text || ' x ' || quantity_total::text, ', ' ORDER BY sort_order) FROM fn_get_quotation_line_components(1, v_q)) = 'QFPANEL 10.000 x 20.000, QFINV 3.000 x 6.000');
    PERFORM pg_temp.ok('the proposal prints the package row, its components, then the next line, in that order',
        (SELECT string_agg(row_kind || ':' || description, ' | ' ORDER BY ord) FROM (SELECT row_number() OVER () AS ord, row_kind, description FROM fn_get_quotation_proposal(1, v_q)) p)
        = 'package:QF 6 kW kit | component:QF Solar panel | component:QF Micro inverter | line:QF Plain item');
    PERFORM pg_temp.ok('a component row carries the multiplied quantity, its make text and no price',
        (SELECT quantity = 20 AND make_text = 'ADANI Warranty 30 years' AND unit_price IS NULL AND line_total IS NULL FROM fn_get_quotation_proposal(1, v_q) WHERE row_kind = 'component' AND description = 'QF Solar panel'));
    PERFORM pg_temp.ok('the package row keeps its own price for the quotation''s totals (2 x 150,000) and the plain item adds 400', (SELECT subtotal FROM fn_get_quotation_by_id(1, v_q)) = 300400);
    -- Overrides: the panel's make text replaced, the inverter's cleared.
    v_lines := '[{"lineType":"package","packageId":' || pg_temp.ctx('pkg') || ',"quantity":1,"components":[{"itemId":' || pg_temp.ctx('panel') || ',"makeText":"Custom make"},{"itemId":' || pg_temp.ctx('inv') || ',"makeText":""}]}]';
    PERFORM pg_temp.save_q(v_q, 0, v_lines, NULL);
    PERFORM pg_temp.ok('a component''s make text can be overridden or cleared per quotation; the re-save replaced the old component rows',
        (SELECT string_agg(coalesce(make_text, '-'), '|' ORDER BY sort_order) FROM fn_get_quotation_line_components(1, v_q)) = 'Custom make|-'
        AND (SELECT count(*) FROM fn_get_quotation_line_components(1, v_q)) = 2);
    PERFORM pg_temp.save_q(v_q, 0, '[{"lineType":"package","packageId":' || pg_temp.ctx('pkg') || ',"quantity":1,"components":[{"itemId":' || pg_temp.ctx('panel') || '}]}]', NULL);
    PERFORM pg_temp.ok('a component with no makeText key takes the item default; one that is not listed does too',
        (SELECT string_agg(coalesce(make_text, '-'), '|' ORDER BY sort_order) FROM fn_get_quotation_line_components(1, v_q)) = 'ADANI Warranty 30 years|DEYE Warranty 10 Years');
END;
$$;
SELECT pg_temp.fails('components of an item that is not in the package are refused', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"package","packageId":%s,"quantity":1,"components":[{"itemId":%s}]}]', NULL)$q$, pg_temp.ctx('q2'), pg_temp.ctx('pkg'), pg_temp.ctx('plain')), '22023', 'lines');
SELECT pg_temp.fails('components on a line that is not a package are refused', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"item","itemId":%s,"quantity":1,"components":[]}]', NULL)$q$, pg_temp.ctx('q2'), pg_temp.ctx('plain')), '22023', 'lines');
SELECT pg_temp.fails('a make text over 300 characters is refused', format($q$SELECT pg_temp.save_q(%s, 0, %L, NULL)$q$, pg_temp.ctx('q2'), '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":1,"makeText":"' || repeat('m', 301) || '"}]'), '22023', 'lines');

-- ---- datasheet lists -------------------------------------------------------------------------------------------------------------------------
SELECT pg_temp.fails('an unknown datasheet id is not found', format($q$CALL sp_set_quotation_datasheets(1, %s, ARRAY[999999999]::bigint[])$q$, pg_temp.ctx('q2')), 'P0002', 'datasheetIds');
SELECT pg_temp.fails('the same datasheet twice is refused', format($q$CALL sp_set_quotation_datasheets(1, %s, ARRAY[%s, %s]::bigint[])$q$, pg_temp.ctx('q2'), pg_temp.ctx('ds1'), pg_temp.ctx('ds1')), '22023', 'datasheetIds');
SELECT pg_temp.fails('a switched-off datasheet cannot be newly added', format($q$CALL sp_set_quotation_datasheets(1, %s, ARRAY[%s]::bigint[])$q$, pg_temp.ctx('q2'), pg_temp.ctx('ds3')), 'NX409', 'datasheetIds');
SELECT pg_temp.fails('more than 20 datasheets are refused', format($q$CALL sp_set_quotation_datasheets(1, %s, ARRAY[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21]::bigint[])$q$, pg_temp.ctx('q2')), '22023', 'datasheetIds');
DO $$
BEGIN
    CALL sp_set_quotation_datasheets(1, pg_temp.ctx('q2'), ARRAY[pg_temp.ctx('ds1'), pg_temp.ctx('ds2')]);
    UPDATE datasheets SET is_active = false WHERE datasheet_id = pg_temp.ctx('ds1');
    CALL sp_set_quotation_datasheets(1, pg_temp.ctx('q2'), ARRAY[pg_temp.ctx('ds2'), pg_temp.ctx('ds1')]);
    PERFORM pg_temp.ok('a datasheet switched off after it was chosen may stay and be reordered on its quotation',
        (SELECT string_agg(datasheet_id::text || ':' || is_active::text, ',' ORDER BY sort_order) FROM fn_get_quotation_datasheets(1, pg_temp.ctx('q2')))
        = pg_temp.ctx('ds2') || ':true,' || pg_temp.ctx('ds1') || ':false');
    CALL sp_set_quotation_datasheets(1, pg_temp.ctx('q2'), ARRAY[]::bigint[]);
    PERFORM pg_temp.ok('an empty list clears the datasheets', NOT EXISTS (SELECT 1 FROM fn_get_quotation_datasheets(1, pg_temp.ctx('q2'))));
    UPDATE datasheets SET is_active = true WHERE datasheet_id = pg_temp.ctx('ds1');
END;
$$;

-- ---- templates and creating a quotation from one --------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_t bigint;
    v_q bigint;
    v_lines text := '[{"lineType":"item","itemId":' || pg_temp.ctx('panel') || ',"quantity":10},{"lineType":"item","itemId":' || pg_temp.ctx('inv') || ',"quantity":3,"makeText":"DEYE (own words)"},'
        || '{"lineType":"custom","description":"KSEB fees","quantity":1,"unitPrice":7180,"isExtraCharge":true}]';
    v_doc text := '{"documentTitle":"6 kW on grid","capacityKw":6,"subsidyCategory":"domestic","showLinePrices":false,"costNotes":"*KSEB extra","paymentTermsHtml":"<p>70/30</p>",'
        || '"termsHtml":"<p>Terms</p>","datasheetIds":[' || pg_temp.ctx('ds1') || ',' || pg_temp.ctx('ds2') || ']}';
    r record;
BEGIN
    CALL sp_save_template(1, NULL, 'QF 6 kW template', NULL, 30, NULL, true, v_lines::jsonb, v_t, v_doc::jsonb);
    PERFORM pg_temp.setctx('tpl', v_t);
    CALL sp_set_template_hero(1, v_t, 'qf-hero.png', 'image/png');
    SELECT * INTO r FROM fn_get_template_by_id(1, v_t);
    PERFORM pg_temp.ok('the template carries its document settings', r.document_title = '6 kW on grid' AND r.capacity_kw = 6 AND r.subsidy_category = 'domestic'
        AND r.show_line_prices = false AND r.cost_notes = '*KSEB extra' AND r.payment_terms_html = '<p>70/30</p>' AND r.terms_html = '<p>Terms</p>' AND r.hero_file_name = 'qf-hero.png');
    PERFORM pg_temp.ok('its lines keep make text and the extra-charge flag', (SELECT string_agg(coalesce(make_text, '-') || '/' || is_extra_charge::text, '|' ORDER BY sort_order) FROM fn_get_template_lines(1, v_t))
        = 'ADANI Warranty 30 years/false|DEYE (own words)/false|-/true');
    PERFORM pg_temp.ok('its datasheets are listed in order', (SELECT string_agg(datasheet_name, ',' ORDER BY sort_order) FROM fn_get_template_datasheets(1, v_t)) = 'Panel datasheet,Inverter datasheet');
    -- Creating a quotation from it: everything is copied, the subsidy comes from the slabs, an inactive datasheet is skipped.
    UPDATE datasheets SET is_active = false WHERE datasheet_id = pg_temp.ctx('ds2');
    v_q := fn_create_quotation_from_template(1, v_t, pg_temp.ctx('cust'), NULL, ARRAY(SELECT template_line_id FROM fn_get_template_lines(1, v_t)), pg_temp.ctx('user')::integer);
    PERFORM pg_temp.setctx('q3', v_q);
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_q);
    PERFORM pg_temp.ok('the quotation starts with the template''s settings and its own subsidy suggestion',
        r.document_title = '6 kW on grid' AND r.capacity_kw = 6 AND r.show_line_prices = false AND r.cost_notes = '*KSEB extra' AND r.terms_html = '<p>Terms</p>'
        AND r.hero_file_name = 'qf-hero.png' AND r.hero_content_type = 'image/png' AND r.subsidy_amount = 78000 AND r.subsidy_overridden = false);
    PERFORM pg_temp.ok('its lines keep the make text and the extra charge; the figures follow (175,000 + 180,000 + 7,180)',
        (SELECT string_agg(coalesce(make_text, '-') || '/' || is_extra_charge::text, '|' ORDER BY sort_order) FROM fn_get_quotation_lines(1, v_q)) = 'ADANI Warranty 30 years/false|DEYE (own words)/false|-/true'
        AND r.subtotal = 362180 AND r.extra_charges_amount = 7180 AND r.customer_payable = 355000);
    PERFORM pg_temp.ok('a datasheet switched off since is left out of the new quotation', (SELECT string_agg(datasheet_name, ',') FROM fn_get_quotation_datasheets(1, v_q)) = 'Panel datasheet');
    UPDATE datasheets SET is_active = true WHERE datasheet_id = pg_temp.ctx('ds2');
    -- A later edit of the template does not touch the quotation made from it.
    CALL sp_save_template(1, v_t, 'QF 6 kW template', NULL, 30, NULL, true, v_lines::jsonb, v_t, '{"documentTitle":"Changed title"}'::jsonb);
    PERFORM pg_temp.ok('editing the template later leaves the quotation alone', (SELECT document_title FROM fn_get_quotation_by_id(1, v_q)) = '6 kW on grid');
    PERFORM pg_temp.ok('a template save without settings keeps them (the old save path)', (SELECT capacity_kw FROM fn_get_template_by_id(1, v_t)) = 6);
    CALL sp_save_template(1, v_t, 'QF 6 kW template', NULL, 30, NULL, true, v_lines::jsonb, v_t, '{"capacityKw":null,"subsidyCategory":null}'::jsonb);
    PERFORM pg_temp.ok('a null clears a template setting; a null category means none', (SELECT capacity_kw IS NULL AND subsidy_category = 'none' FROM fn_get_template_by_id(1, v_t)));
END;
$$;
SELECT pg_temp.fails('a template with a bad HTML text is refused', format($q$CALL sp_save_template(1, %s, 'x', NULL, 30, NULL, true, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":1}]'::jsonb, NULL, '{"termsHtml":"<a href=\"x\">x</a>"}'::jsonb)$q$, pg_temp.ctx('tpl')), '22023', 'termsHtml');
SELECT pg_temp.fails('a template hero needs a type', format($q$CALL sp_set_template_hero(1, %s, 'x.gif', 'image/gif')$q$, pg_temp.ctx('tpl')), '22023', 'image');

-- ---- the company snapshot taken when a quotation is sent ---------------------------------------------------------------------------------------
DO $$
DECLARE
    v_q bigint := pg_temp.ctx('q3');
    r record;
    v_prev varchar;
BEGIN
    CALL sp_save_company_profile(1, '{"displayName":"Snapshot Solar","addressLine1":"1 Old Road","gstin":"32AORPD4052J1Z0","pan":"AORPD4052J","bankName":"AXIS Bank","bankBranch":"Neyyattinkara","bankAccountName":"Snapshot Solar","bankAccountNumber":"922020059631078","bankIfsc":"UTIB0004076"}'::jsonb, pg_temp.ctx('user')::integer);
    CALL sp_set_company_logo(1, 'qf-logo-1.png', 'image/png', pg_temp.ctx('user')::integer, v_prev);
    SELECT * INTO r FROM fn_get_quotation_company(1, v_q);
    PERFORM pg_temp.ok('a draft prints the live company profile', r.from_snapshot = false AND r.display_name = 'Snapshot Solar' AND r.bank_branch = 'Neyyattinkara');
    CALL sp_set_quotation_status(1, v_q, 'sent', pg_temp.ctx('user')::integer, NULL);
    PERFORM pg_temp.ok('sending freezes a snapshot', (SELECT has_company_snapshot FROM fn_get_quotation_by_id(1, v_q)));
    CALL sp_save_company_profile(1, '{"displayName":"Renamed Solar","addressLine1":"2 New Road","gstin":"32AORPD4052J1Z0","bankName":"SBI","bankBranch":"Elsewhere","website":"https://new.example"}'::jsonb, pg_temp.ctx('user')::integer);
    SELECT * INTO r FROM fn_get_quotation_company(1, v_q);
    PERFORM pg_temp.ok('after the profile changes, the sent quotation still prints what it was sent with',
        r.from_snapshot AND r.display_name = 'Snapshot Solar' AND r.address_line1 = '1 Old Road' AND r.bank_name = 'AXIS Bank' AND r.bank_branch = 'Neyyattinkara'
        AND r.bank_account_number = '922020059631078' AND r.pan = 'AORPD4052J' AND r.logo_file_name = 'qf-logo-1.png');
    PERFORM pg_temp.ok('a field that was empty when it was sent stays empty on the reprint even though the profile has it now', r.website IS NULL);
    CALL sp_set_company_logo(1, 'qf-logo-2.png', 'image/png', pg_temp.ctx('user')::integer, v_prev);
    PERFORM pg_temp.ok('a logo that a sent quotation still points at is not handed back for deletion', v_prev IS NULL);
    CALL sp_set_company_logo(1, 'qf-logo-3.png', 'image/png', pg_temp.ctx('user')::integer, v_prev);
    PERFORM pg_temp.ok('a logo nobody points at is handed back as before', v_prev = 'qf-logo-2.png');
    PERFORM pg_temp.ok('a new draft quotation prints the NEW profile', (SELECT display_name FROM fn_get_quotation_company(1, pg_temp.ctx('q2'))) = 'Renamed Solar');
    PERFORM pg_temp.ok('the profile reads back the new fields', (SELECT bank_branch FROM fn_get_company_profile(1)) = 'Elsewhere');
END;
$$;
SELECT pg_temp.fails('a draft cannot hold a snapshot (the table refuses it)', format($q$UPDATE quotations SET company_snapshot = '{}'::jsonb WHERE quotation_id = %s$q$, pg_temp.ctx('q2')), '23514');
SELECT pg_temp.fails('a sent quotation can no longer change its datasheets', format($q$CALL sp_set_quotation_datasheets(1, %s, ARRAY[]::bigint[])$q$, pg_temp.ctx('q3')), 'NX409');
SELECT pg_temp.fails('a sent quotation can no longer change its hero picture', format($q$CALL sp_set_quotation_hero(1, %s, 'x.png', 'image/png')$q$, pg_temp.ctx('q3')), 'NX409');
SELECT pg_temp.fails('a sent quotation can no longer be saved', format($q$SELECT pg_temp.save_q(%s, 0, '[{"lineType":"custom","description":"x","quantity":1,"unitPrice":1}]', NULL)$q$, pg_temp.ctx('q3')), 'NX409');

-- ---- company defaults and the bank branch -----------------------------------------------------------------------------------------------------
DO $$
BEGIN
    CALL sp_save_company_profile(1, '{"displayName":"Defaults Solar","bankBranch":"Main","defaultPaymentTermsHtml":"<p>70% advance</p>","defaultTermsHtml":"<ul><li>Valid</li></ul>","defaultCostNotes":"*KSEB extra"}'::jsonb, pg_temp.ctx('user')::integer);
    PERFORM pg_temp.ok('the company defaults are saved', (SELECT default_payment_terms_html = '<p>70% advance</p>' AND default_terms_html = '<ul><li>Valid</li></ul>' AND default_cost_notes = '*KSEB extra' AND bank_branch = 'Main'
                                                          FROM fn_get_company_profile(1)));
    -- A caller that does not know these keys (an older screen) must not wipe them.
    CALL sp_save_company_profile(1, '{"displayName":"Defaults Solar"}'::jsonb, pg_temp.ctx('user')::integer);
    PERFORM pg_temp.ok('a save without the new keys leaves them alone', (SELECT bank_branch = 'Main' AND default_terms_html IS NOT NULL AND default_cost_notes IS NOT NULL FROM fn_get_company_profile(1)));
    CALL sp_save_company_profile(1, '{"displayName":"Defaults Solar","bankBranch":"","defaultCostNotes":null}'::jsonb, pg_temp.ctx('user')::integer);
    PERFORM pg_temp.ok('a blank or null new key clears it', (SELECT bank_branch IS NULL AND default_cost_notes IS NULL AND default_terms_html IS NOT NULL FROM fn_get_company_profile(1)));
END;
$$;
SELECT pg_temp.fails('default terms with a script tag are refused', $q$CALL sp_save_company_profile(1, '{"defaultTermsHtml":"<script>x</script>"}'::jsonb, 1)$q$, '22023', 'defaultTermsHtml');
SELECT pg_temp.fails('a branch over 150 characters is refused', format($q$CALL sp_save_company_profile(1, %L::jsonb, 1)$q$, '{"bankBranch":"' || repeat('b', 151) || '"}'), '22023', 'bankBranch');

-- ---- converting to an order keeps the extra-charge subtotal ----------------------------------------------------------------------------------
DO $$
DECLARE
    v_q bigint := pg_temp.ctx('q3');
    v_o bigint;
    r record;
BEGIN
    CALL sp_set_quotation_status(1, v_q, 'approved', pg_temp.ctx('user')::integer, NULL);
    v_o := fn_convert_quotation_to_order(1, v_q, pg_temp.ctx('user')::integer);
    SELECT * INTO r FROM fn_get_order_by_id(1, v_o);
    PERFORM pg_temp.ok('the order carries the total (362,180) and the extra-charge subtotal (7,180)', r.total_amount = 362180 AND r.extra_charges_amount = 7180);
    PERFORM pg_temp.ok('the order lines carry the extra-charge flag', (SELECT string_agg(is_extra_charge::text, ',' ORDER BY sort_order) FROM fn_get_order_lines(1, v_o)) = 'false,false,true');
    PERFORM pg_temp.ok('the snapshot stays on the quotation after the conversion', (SELECT has_company_snapshot FROM fn_get_quotation_by_id(1, v_q)));
END;
$$;

-- ---- duplicating a quotation ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_new bigint;
    r record;
BEGIN
    CALL sp_duplicate_quotation(1, pg_temp.ctx('q3'), pg_temp.ctx('user')::integer, v_new);
    SELECT * INTO r FROM fn_get_quotation_by_id(1, v_new);
    PERFORM pg_temp.ok('a duplicate is a draft with the settings, extra charges, hero and datasheets of the original',
        r.status = 'draft' AND r.document_title = '6 kW on grid' AND r.extra_charges_amount = 7180 AND r.subsidy_amount = 78000 AND r.hero_file_name = 'qf-hero.png'
        AND r.show_line_prices = false AND r.terms_html = '<p>Terms</p>' AND (SELECT count(*) FROM fn_get_quotation_datasheets(1, v_new)) = 1);
    PERFORM pg_temp.ok('a duplicate of a sent quotation has no company snapshot (it reads the live profile)', r.has_company_snapshot = false);
    PERFORM pg_temp.ok('the duplicate keeps the lines'' make text and flags', (SELECT string_agg(coalesce(make_text, '-') || '/' || is_extra_charge::text, '|' ORDER BY sort_order) FROM fn_get_quotation_lines(1, v_new))
        = 'ADANI Warranty 30 years/false|DEYE (own words)/false|-/true');
    -- A duplicate of a package quotation copies the component rows (and their overrides) onto the right lines.
    PERFORM pg_temp.save_q(pg_temp.ctx('q2'), 0, '[{"lineType":"package","packageId":' || pg_temp.ctx('pkg') || ',"quantity":1,"components":[{"itemId":' || pg_temp.ctx('panel') || ',"makeText":"Kept override"}]}]', NULL);
    CALL sp_duplicate_quotation(1, pg_temp.ctx('q2'), pg_temp.ctx('user')::integer, v_new);
    PERFORM pg_temp.ok('a duplicate copies the package components with their overrides',
        (SELECT string_agg(coalesce(make_text, '-'), '|' ORDER BY sort_order) FROM fn_get_quotation_line_components(1, v_new)) = 'Kept override|DEYE Warranty 10 Years');
END;
$$;

-- ---- the item's default make text (set on the item screen) ---------------------------------------------------------------------------------------
DO $$
DECLARE
    v_unit varchar := (SELECT unit_code FROM units WHERE tenant_id = 1 AND is_active ORDER BY unit_code LIMIT 1);
    v_item bigint;
BEGIN
    v_item := fn_save_item(1, NULL, 'QFMAKE1', 'QF make item', v_unit, 0, 100, 0, '  Waaree 25 years  ');
    PERFORM pg_temp.ok('an item saves its make text trimmed and both reads return it',
        (SELECT make_text FROM fn_get_item_by_id(1, v_item)) = 'Waaree 25 years'
        AND (SELECT make_text FROM fn_get_items(1, 'QFMAKE1', false)) = 'Waaree 25 years');
    PERFORM fn_save_item(1, v_item, 'QFMAKE1', 'QF make item', v_unit, 0, 100, 0, '   ');
    PERFORM pg_temp.ok('a blank make text clears it', (SELECT make_text FROM fn_get_item_by_id(1, v_item)) IS NULL);
    PERFORM fn_save_item(1, v_item, 'QFMAKE1', 'QF make item', v_unit, 0, 100, 0);
    PERFORM pg_temp.ok('the old eight-argument call still works and leaves no make text', (SELECT make_text FROM fn_get_item_by_id(1, v_item)) IS NULL);
END;
$$;

-- ---- tenant isolation ----------------------------------------------------------------------------------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.ok('tenant 2 sees none of tenant 1''s documents, datasheets, components or company',
        NOT EXISTS (SELECT 1 FROM fn_get_quotation_by_id(2, pg_temp.ctx('q1'))) AND NOT EXISTS (SELECT 1 FROM fn_get_quotation_proposal(2, pg_temp.ctx('q2')))
        AND NOT EXISTS (SELECT 1 FROM fn_get_quotation_line_components(2, pg_temp.ctx('q2'))) AND NOT EXISTS (SELECT 1 FROM fn_get_quotation_company(2, pg_temp.ctx('q1')))
        AND NOT EXISTS (SELECT 1 FROM fn_get_datasheets(2, true)) AND NOT EXISTS (SELECT 1 FROM fn_get_quotation_datasheets(2, pg_temp.ctx('q3')))
        AND NOT EXISTS (SELECT 1 FROM fn_get_template_by_id(2, pg_temp.ctx('tpl'))) AND fn_template_document(2, pg_temp.ctx('tpl')) IS NULL);
END;
$$;
SELECT pg_temp.fails('tenant 2 cannot choose tenant 1''s datasheet', format($q$CALL sp_check_datasheet_ids(2, ARRAY[%s]::bigint[], NULL)$q$, pg_temp.ctx('ds1')), 'P0002', 'datasheetIds');

SELECT count(*) || ' checks passed' AS result FROM t_pass;
ROLLBACK;
SELECT count(*) AS rows_left_behind FROM items WHERE item_code LIKE 'QF%';
