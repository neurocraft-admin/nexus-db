-- Quotation templates, by name. p_active_only true leaves out deactivated templates (the quotation editor's list);
-- false returns all (the templates screen).
CREATE OR REPLACE FUNCTION fn_get_templates(p_tenant_id integer, p_active_only boolean)
RETURNS TABLE (template_id bigint, template_name varchar, description varchar, default_validity_days integer,
               is_active boolean, line_count bigint, updated_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT t.template_id, t.template_name, t.description, t.default_validity_days, t.is_active,
           (SELECT count(*) FROM quotation_template_lines l WHERE l.template_id = t.template_id), t.updated_at
      FROM quotation_templates t
     WHERE t.tenant_id = p_tenant_id
       AND (NOT COALESCE(p_active_only, false) OR t.is_active)
     ORDER BY t.template_name, t.template_id;
$$;
