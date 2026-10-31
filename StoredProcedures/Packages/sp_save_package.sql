-- One transaction: insert (p_package_id NULL) or update the header, and replace all the lines. Returns the id in
-- p_saved_id. p_lines is a JSON array of {"itemId": 1, "quantity": 2.5}. The price is tax-inclusive and typed in;
-- it must be above zero. A price below the component cost is allowed (the API warns, it does not block).
--   23505 unique_violation  - the package code exists (uq_packages_tenant_code), inactive packages included
--   23514 check violation   - code not upper case letters/digits/. _ / -
--   22023 invalid parameter - price not above zero (COLUMN packagePrice), or the line rules of sp_check_package_lines
--   P0002 not found         - unknown package on update, or an unknown item
--   NX409 rule conflict     - an inactive item in the lines
-- The package row is locked first, then the items in id order, so two saves of the same package queue up instead of
-- mixing their lines.
CREATE OR REPLACE PROCEDURE sp_save_package(
    p_tenant_id integer, p_package_id bigint, p_package_code varchar, p_package_name varchar,
    p_description varchar, p_package_price numeric, p_lines jsonb, OUT p_saved_id bigint)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_package_price IS NULL OR p_package_price <= 0 THEN
        RAISE EXCEPTION 'The package price must be above zero' USING ERRCODE = '22023', COLUMN = 'packagePrice';
    END IF;
    IF p_package_id IS NOT NULL THEN
        PERFORM 1 FROM packages p WHERE p.package_id = p_package_id AND p.tenant_id = p_tenant_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Package % not found', p_package_id USING ERRCODE = 'P0002';
        END IF;
    END IF;
    CALL sp_check_package_lines(p_tenant_id, p_lines);

    IF p_package_id IS NULL THEN
        INSERT INTO packages (tenant_id, package_code, package_name, description, package_price)
        VALUES (p_tenant_id, p_package_code, p_package_name, p_description, p_package_price)
        RETURNING packages.package_id INTO p_saved_id;
    ELSE
        UPDATE packages
           SET package_code = p_package_code, package_name = p_package_name, description = p_description,
               package_price = p_package_price, updated_at = now()
         WHERE packages.package_id = p_package_id AND packages.tenant_id = p_tenant_id
        RETURNING packages.package_id INTO p_saved_id;
    END IF;
    CALL sp_replace_package_lines(p_tenant_id, p_saved_id, p_lines);
END;
$$;
