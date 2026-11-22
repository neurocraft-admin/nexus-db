-- The subsidy slabs, by category and capacity. Inactive slabs are listed only when asked for. capacity_to_kw NULL means no upper bound.
CREATE OR REPLACE FUNCTION fn_get_subsidy_slabs(p_tenant_id integer, p_include_inactive boolean)
RETURNS TABLE (slab_id bigint, category_code varchar, category_name varchar, capacity_from_kw numeric, capacity_to_kw numeric,
               amount numeric, is_active boolean, updated_by_name varchar, updated_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT s.slab_id, s.category_code, c.category_name, s.capacity_from_kw, s.capacity_to_kw, s.amount, s.is_active, u.full_name, s.updated_at
      FROM subsidy_slabs s
      JOIN subsidy_categories c ON c.tenant_id = s.tenant_id AND c.category_code = s.category_code
      LEFT JOIN users u ON u.user_id = s.updated_by
     WHERE s.tenant_id = p_tenant_id AND (COALESCE(p_include_inactive, false) OR s.is_active)
     ORDER BY c.sort_order, s.category_code, s.capacity_from_kw, s.slab_id;
$$;
