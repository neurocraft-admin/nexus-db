-- Validates an ordered list of datasheet ids chosen for a template or a quotation. p_keep are the ids already on that document: a datasheet that was
-- switched off after it was chosen may stay on it, but cannot be newly added.
--   22023 invalid parameter - more than 20, a number that is not positive, or the same datasheet twice (COLUMN datasheetIds)
--   P0002 not found         - an id that is not a datasheet of this company
--   NX409 rule conflict     - a switched-off datasheet that is not already on the document
CREATE OR REPLACE PROCEDURE sp_check_datasheet_ids(p_tenant_id integer, p_ids bigint[], p_keep bigint[])
LANGUAGE plpgsql AS $$
DECLARE
    c_max CONSTANT integer := 20;
    v_list text;
BEGIN
    IF cardinality(p_ids) > c_max OR EXISTS (SELECT 1 FROM unnest(p_ids) AS x WHERE x IS NULL OR x <= 0)
       OR (SELECT count(DISTINCT x) FROM unnest(p_ids) AS x) <> cardinality(p_ids) THEN
        RAISE EXCEPTION 'Choose up to % different datasheets', c_max USING ERRCODE = '22023', COLUMN = 'datasheetIds';
    END IF;
    SELECT string_agg(x::text, ', ' ORDER BY x) INTO v_list FROM unnest(p_ids) AS x
     WHERE NOT EXISTS (SELECT 1 FROM datasheets d WHERE d.datasheet_id = x AND d.tenant_id = p_tenant_id);
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'Datasheets not found: %', v_list USING ERRCODE = 'P0002', COLUMN = 'datasheetIds';
    END IF;
    SELECT string_agg(d.datasheet_name, ', ' ORDER BY d.datasheet_id) INTO v_list FROM datasheets d
     WHERE d.tenant_id = p_tenant_id AND NOT d.is_active AND d.datasheet_id = ANY (p_ids) AND NOT (d.datasheet_id = ANY (COALESCE(p_keep, ARRAY[]::bigint[])));
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'Switched-off datasheets cannot be added: %', v_list USING ERRCODE = 'NX409', COLUMN = 'datasheetIds';
    END IF;
END;
$$;
