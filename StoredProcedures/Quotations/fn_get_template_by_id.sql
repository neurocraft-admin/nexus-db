-- One quotation template's header (its lines are fn_get_template_lines). No rows when it does not exist.
CREATE OR REPLACE FUNCTION fn_get_template_by_id(p_tenant_id integer, p_template_id bigint)
RETURNS TABLE (template_id bigint, template_name varchar, description varchar, default_validity_days integer,
               terms_text varchar, is_active boolean, created_at timestamptz, updated_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT t.template_id, t.template_name, t.description, t.default_validity_days, t.terms_text, t.is_active,
           t.created_at, t.updated_at
      FROM quotation_templates t
     WHERE t.tenant_id = p_tenant_id AND t.template_id = p_template_id;
$$;
