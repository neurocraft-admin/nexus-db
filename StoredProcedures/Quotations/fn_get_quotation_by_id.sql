-- One quotation with the names of its customer or lead, template, revision source, creator and order, and its document settings:
--   document_title, hero_file_name / hero_content_type, capacity_kw, subsidy_category and its name, subsidy_amount, subsidy_overridden (the amount was
--   typed, not taken from the slabs), suggested_subsidy (what the slabs suggest NOW for the capacity; NULL when none), show_line_prices, cost_notes,
--   payment_terms_html, terms_html (restricted HTML), has_company_snapshot (the company details were frozen when it was sent).
-- The figures: subtotal (all lines), extra_charges_amount (pass-through lines, inside the total), discount_amount, total_amount = subtotal - discount,
--   customer_payable = subtotal - extra charges - discount, after_subsidy = customer_payable - subsidy.
-- PL/pgSQL (not SQL) because it calls fn_suggest_subsidy, which is applied after this file on an empty database.
-- customer_address / lead_address are the address of the party the quotation is addressed to. The quotation is returned whatever its status.
DROP FUNCTION IF EXISTS fn_get_quotation_by_id(integer, bigint);
CREATE OR REPLACE FUNCTION fn_get_quotation_by_id(p_tenant_id integer, p_quotation_id bigint)
RETURNS TABLE (quotation_id bigint, quotation_no varchar, customer_id bigint, customer_name varchar,
               customer_mobile varchar, lead_id bigint, lead_no varchar, lead_name varchar, lead_mobile varchar,
               template_id bigint, template_name varchar,
               revision_of_id bigint, revision_of_no varchar, status varchar, quotation_date date, valid_until date,
               subtotal numeric, discount_amount numeric, total_amount numeric, terms_text varchar, notes varchar,
               created_by integer, created_by_name varchar, sent_at timestamptz, decided_at timestamptz,
               order_id bigint, order_no varchar, created_at timestamptz, updated_at timestamptz,
               document_title varchar, hero_file_name varchar, hero_content_type varchar, capacity_kw numeric, subsidy_category varchar,
               subsidy_category_name varchar, subsidy_amount numeric, subsidy_overridden boolean, suggested_subsidy numeric,
               show_line_prices boolean, cost_notes varchar, payment_terms_html varchar, terms_html varchar, extra_charges_amount numeric,
               customer_payable numeric, after_subsidy numeric, has_company_snapshot boolean, customer_address varchar, lead_address varchar)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT q.quotation_id, q.quotation_no, q.customer_id, c.customer_name, c.mobile, q.lead_id, ld.lead_no, ld.lead_name,
           ld.mobile, q.template_id, t.template_name, q.revision_of_id, r.quotation_no, q.status, q.quotation_date,
           q.valid_until, q.subtotal, q.discount_amount, q.total_amount, q.terms_text, q.notes, q.created_by, u.full_name,
           q.sent_at, q.decided_at, o.order_id, o.order_no, q.created_at, q.updated_at,
           q.document_title, q.hero_file_name, q.hero_content_type, q.capacity_kw, q.subsidy_category, sc.category_name, q.subsidy_amount,
           q.subsidy_overridden, fn_suggest_subsidy(q.tenant_id, q.subsidy_category, q.capacity_kw), q.show_line_prices, q.cost_notes,
           q.payment_terms_html, q.terms_html, q.extra_charges_amount, q.subtotal - q.extra_charges_amount - q.discount_amount,
           q.subtotal - q.extra_charges_amount - q.discount_amount - q.subsidy_amount, q.company_snapshot IS NOT NULL, c.address, ld.address
      FROM quotations q
      LEFT JOIN customers c ON c.customer_id = q.customer_id
      LEFT JOIN leads ld ON ld.lead_id = q.lead_id
      LEFT JOIN quotation_templates t ON t.template_id = q.template_id
      LEFT JOIN quotations r ON r.quotation_id = q.revision_of_id
      LEFT JOIN users u ON u.user_id = q.created_by AND u.tenant_id = q.tenant_id
      LEFT JOIN orders o ON o.quotation_id = q.quotation_id
      LEFT JOIN subsidy_categories sc ON sc.tenant_id = q.tenant_id AND sc.category_code = q.subsidy_category
     WHERE q.tenant_id = p_tenant_id AND q.quotation_id = p_quotation_id;
END;
$$;
