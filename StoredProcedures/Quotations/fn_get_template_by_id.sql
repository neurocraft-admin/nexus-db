-- One quotation template with its document settings (title, hero image, capacity, subsidy category, whether line prices are shown, cost-page
-- notes, payment terms and terms and conditions as restricted HTML). Its lines are fn_get_template_lines and its datasheets
-- fn_get_template_datasheets.
DROP FUNCTION IF EXISTS fn_get_template_by_id(integer, bigint);
CREATE OR REPLACE FUNCTION fn_get_template_by_id(p_tenant_id integer, p_template_id bigint)
RETURNS TABLE (template_id bigint, template_name varchar, description varchar, default_validity_days integer,
               terms_text varchar, is_active boolean, created_at timestamptz, updated_at timestamptz,
               document_title varchar, hero_file_name varchar, hero_content_type varchar, capacity_kw numeric, subsidy_category varchar,
               show_line_prices boolean, cost_notes varchar, payment_terms_html varchar, terms_html varchar)
LANGUAGE sql STABLE AS $$
    SELECT t.template_id, t.template_name, t.description, t.default_validity_days, t.terms_text, t.is_active,
           t.created_at, t.updated_at, t.document_title, t.hero_file_name, t.hero_content_type, t.capacity_kw, t.subsidy_category,
           t.show_line_prices, t.cost_notes, t.payment_terms_html, t.terms_html
      FROM quotation_templates t
     WHERE t.tenant_id = p_tenant_id AND t.template_id = p_template_id;
$$;
