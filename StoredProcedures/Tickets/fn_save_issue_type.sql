-- Insert (p_issue_type_id NULL) or update an issue type and return its id. The table stays the source of truth: a type
-- can equally be added by script. A type in use can be switched off: its tickets keep it and it leaves the dropdown.
--   22023 invalid parameter - empty or too long name (COLUMN issueTypeName)
--   23505 unique_violation  - another type has this name, ignoring case (uq_issue_types_tenant_name)
--   P0002 not found         - unknown type on update
CREATE OR REPLACE FUNCTION fn_save_issue_type(
    p_tenant_id integer, p_issue_type_id integer, p_issue_type_name varchar, p_sort_order integer, p_is_active boolean)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    v_issue_type_id integer;
BEGIN
    IF p_issue_type_name IS NULL OR btrim(p_issue_type_name) = '' OR length(btrim(p_issue_type_name)) > 100 THEN
        RAISE EXCEPTION 'An issue type needs a name of up to 100 characters' USING ERRCODE = '22023', COLUMN = 'issueTypeName';
    END IF;
    IF p_issue_type_id IS NULL THEN
        INSERT INTO issue_types (tenant_id, issue_type_name, sort_order, is_active)
        VALUES (p_tenant_id, btrim(p_issue_type_name), COALESCE(p_sort_order, 0), COALESCE(p_is_active, true))
        RETURNING issue_types.issue_type_id INTO v_issue_type_id;
    ELSE
        UPDATE issue_types
           SET issue_type_name = btrim(p_issue_type_name), sort_order = COALESCE(p_sort_order, sort_order),
               is_active = COALESCE(p_is_active, is_active), updated_at = now()
         WHERE issue_types.issue_type_id = p_issue_type_id AND issue_types.tenant_id = p_tenant_id
        RETURNING issue_types.issue_type_id INTO v_issue_type_id;
        IF v_issue_type_id IS NULL THEN
            RAISE EXCEPTION 'Issue type % not found', p_issue_type_id USING ERRCODE = 'P0002';
        END IF;
    END IF;
    RETURN v_issue_type_id;
END;
$$;
