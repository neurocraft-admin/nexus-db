-- Active units for the item form's dropdown, in the order they should be shown.
CREATE OR REPLACE FUNCTION fn_get_units(p_tenant_id integer)
RETURNS TABLE (unit_code varchar, unit_name varchar)
LANGUAGE sql STABLE AS $$
    SELECT u.unit_code, u.unit_name
      FROM units u
     WHERE u.tenant_id = p_tenant_id
       AND u.is_active
     ORDER BY u.sort_order, u.unit_code;
$$;
