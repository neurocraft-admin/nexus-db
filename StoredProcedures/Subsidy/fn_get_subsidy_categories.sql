-- The subsidy categories of a company (none, domestic, commercial, ...), in their display order. has_subsidy says whether slabs and an amount apply.
CREATE OR REPLACE FUNCTION fn_get_subsidy_categories(p_tenant_id integer)
RETURNS TABLE (category_code varchar, category_name varchar, has_subsidy boolean, sort_order integer)
LANGUAGE sql STABLE AS $$
    SELECT c.category_code, c.category_name, c.has_subsidy, c.sort_order
      FROM subsidy_categories c
     WHERE c.tenant_id = p_tenant_id AND c.is_active
     ORDER BY c.sort_order, c.category_code;
$$;
