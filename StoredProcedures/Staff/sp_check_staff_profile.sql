-- Checks the role and the profile fields fn_save_staff is given, before anything is written; the table's CHECKs repeat them.
--   22023 invalid parameter - employee code over 30, designation over 100, notes over 500, an alternate mobile that is not a ten-digit
--                             mobile starting 6-9 (COLUMN employeeCode, designation, notes, mobileAlt)
--   P0002 not found         - unknown or inactive role (COLUMN roleId)
CREATE OR REPLACE PROCEDURE sp_check_staff_profile(
    p_tenant_id integer, p_role_id integer, p_employee_code varchar, p_designation varchar, p_mobile_alt varchar, p_notes varchar)
LANGUAGE plpgsql AS $$
DECLARE
    c_code_max        CONSTANT integer := 30;
    c_designation_max CONSTANT integer := 100;
    c_notes_max       CONSTANT integer := 500;
BEGIN
    PERFORM 1 FROM roles r WHERE r.role_id = p_role_id AND r.tenant_id = p_tenant_id AND r.is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Role % not found', p_role_id USING ERRCODE = 'P0002', COLUMN = 'roleId';
    END IF;
    IF length(btrim(COALESCE(p_employee_code, ''))) > c_code_max THEN
        RAISE EXCEPTION 'The employee code can be up to % characters', c_code_max USING ERRCODE = '22023', COLUMN = 'employeeCode';
    END IF;
    IF length(btrim(COALESCE(p_designation, ''))) > c_designation_max THEN
        RAISE EXCEPTION 'The designation can be up to % characters', c_designation_max USING ERRCODE = '22023', COLUMN = 'designation';
    END IF;
    IF length(btrim(COALESCE(p_notes, ''))) > c_notes_max THEN
        RAISE EXCEPTION 'Notes can be up to % characters', c_notes_max USING ERRCODE = '22023', COLUMN = 'notes';
    END IF;
    IF NULLIF(btrim(p_mobile_alt), '') IS NOT NULL AND btrim(p_mobile_alt) !~ '^[6-9][0-9]{9}$' THEN
        RAISE EXCEPTION 'The alternate mobile is ten digits starting 6 to 9' USING ERRCODE = '22023', COLUMN = 'mobileAlt';
    END IF;
END;
$$;
