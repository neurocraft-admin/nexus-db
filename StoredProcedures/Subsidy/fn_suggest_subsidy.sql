-- The subsidy the slab table suggests for a category and a capacity: the amount of the ACTIVE slab of that category whose range holds the capacity
-- (capacity_from_kw <= capacity < capacity_to_kw, or no upper bound). NULL when the category has no subsidy, the capacity is unknown or no slab
-- matches; nothing is invented. Two active slabs of a category never overlap, so there is at most one match.
CREATE OR REPLACE FUNCTION fn_suggest_subsidy(p_tenant_id integer, p_category_code varchar, p_capacity_kw numeric)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT s.amount
      FROM subsidy_slabs s
      JOIN subsidy_categories c ON c.tenant_id = s.tenant_id AND c.category_code = s.category_code
     WHERE s.tenant_id = p_tenant_id AND s.category_code = p_category_code AND s.is_active AND c.is_active AND c.has_subsidy
       AND p_capacity_kw IS NOT NULL AND s.capacity_from_kw <= p_capacity_kw
       AND (s.capacity_to_kw IS NULL OR p_capacity_kw < s.capacity_to_kw)
     ORDER BY s.capacity_from_kw DESC
     LIMIT 1;
$$;
