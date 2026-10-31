-- Copies a package (header, price and lines) under a new code and returns its id in p_new_id. The code is the
-- source code plus -COPY, then -COPY2, -COPY3 ... when that is taken. The source code is shortened first so the
-- result never exceeds the 30 characters a code may have, and the name gets " (copy)" within its 150. The copy is
-- active. If a component of the source has been deactivated the copy carries it and shows "Needs attention".
--   P0002 not found - unknown package
-- An advisory lock serialises duplicates per tenant, so two copies cannot pick the same code.
CREATE OR REPLACE PROCEDURE sp_duplicate_package(p_tenant_id integer, p_package_id bigint, OUT p_new_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    c_code_max    CONSTANT integer := 30;
    c_name_max    CONSTANT integer := 150;
    c_name_suffix CONSTANT varchar := ' (copy)';
    v_code varchar; v_name varchar; v_description varchar; v_price numeric;
    v_attempt integer := 1; v_suffix varchar; v_new_code varchar;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('package_duplicate'), p_tenant_id);
    SELECT p.package_code, p.package_name, p.description, p.package_price
      INTO v_code, v_name, v_description, v_price
      FROM packages p WHERE p.package_id = p_package_id AND p.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Package % not found', p_package_id USING ERRCODE = 'P0002';
    END IF;

    LOOP
        v_suffix := '-COPY' || CASE WHEN v_attempt = 1 THEN '' ELSE v_attempt::text END;
        v_new_code := left(v_code, c_code_max - length(v_suffix)) || v_suffix;
        EXIT WHEN NOT EXISTS (SELECT 1 FROM packages p WHERE p.tenant_id = p_tenant_id AND p.package_code = v_new_code);
        v_attempt := v_attempt + 1;
    END LOOP;

    INSERT INTO packages (tenant_id, package_code, package_name, description, package_price)
    VALUES (p_tenant_id, v_new_code, left(v_name, c_name_max - length(c_name_suffix)) || c_name_suffix,
            v_description, v_price)
    RETURNING packages.package_id INTO p_new_id;
    INSERT INTO package_lines (tenant_id, package_id, item_id, quantity, sort_order)
    SELECT pl.tenant_id, p_new_id, pl.item_id, pl.quantity, pl.sort_order
      FROM package_lines pl WHERE pl.package_id = p_package_id AND pl.tenant_id = p_tenant_id;
    CALL sp_refresh_package_cost(p_tenant_id, p_new_id);
END;
$$;
