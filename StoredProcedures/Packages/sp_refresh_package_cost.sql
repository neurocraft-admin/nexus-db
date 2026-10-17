-- Records the package's current component cost as component_cost_at_save (and stamps updated_at). Called by
-- sp_replace_package_lines and sp_duplicate_package, inside their transaction. The live figure always comes from
-- vw_package_summary; this snapshot only exists so the screen can say the cost has moved since the price was set.
CREATE OR REPLACE PROCEDURE sp_refresh_package_cost(p_tenant_id integer, p_package_id bigint)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE packages
       SET component_cost_at_save = COALESCE((SELECT s.component_cost FROM vw_package_summary s
                                               WHERE s.tenant_id = p_tenant_id AND s.package_id = p_package_id), 0),
           updated_at = now()
     WHERE package_id = p_package_id AND tenant_id = p_tenant_id;
END;
$$;
