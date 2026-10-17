-- Replaces ALL the lines of a package with p_lines (already checked by sp_check_package_lines), keeping their
-- order, then refreshes the cost snapshot. It deletes first, so it only ever runs inside sp_save_package's
-- transaction: if the insert fails (for example a quantity too large for numeric(12,3), 22003) everything rolls
-- back and the old lines are still there.
CREATE OR REPLACE PROCEDURE sp_replace_package_lines(p_tenant_id integer, p_package_id bigint, p_lines jsonb)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM package_lines WHERE package_id = p_package_id AND tenant_id = p_tenant_id;

    INSERT INTO package_lines (tenant_id, package_id, item_id, quantity, sort_order)
    -- jsonb_array_elements (not jsonb_to_recordset) because WITH ORDINALITY, which keeps the order, cannot be
    -- combined with a column definition list.
    SELECT p_tenant_id, p_package_id, (e.line ->> 'itemId')::bigint, (e.line ->> 'quantity')::numeric, e.ord::integer
      FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS e (line, ord);

    CALL sp_refresh_package_cost(p_tenant_id, p_package_id);
END;
$$;
