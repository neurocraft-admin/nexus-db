-- Validates the "components" of the lines of a quotation: the make text of the component items of a PACKAGE line, which the technical proposal
-- prints as separate rows. p_lines is the same JSON array as sp_check_document_lines; a package line may carry
--   "components": [{"itemId": 12, "makeText": "ADANI Warranty 30 years"}]
-- (makeText optional: a component that is not listed, or has no makeText key, takes the item's default make text; a null or blank makeText means
-- none). Only a package line may have components, each itemId must be an item of THAT package, and makeText is up to 300 characters.
-- Call it after sp_check_document_lines and sp_check_document_references (it relies on both).
--   22023 invalid parameter - components on a line that is not a package, a bad entry, or an item that is not in the package (COLUMN lines)
CREATE OR REPLACE PROCEDURE sp_check_line_components(p_tenant_id integer, p_lines jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    v_list text;
BEGIN
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) AS e (line)
                WHERE jsonb_typeof(e.line -> 'components') IS NOT NULL AND jsonb_typeof(e.line -> 'components') <> 'null'
                  AND (jsonb_typeof(e.line -> 'components') <> 'array' OR e.line ->> 'lineType' <> 'package')) THEN
        RAISE EXCEPTION 'Only a package line has components' USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) AS e (line)
                CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(e.line -> 'components') = 'array' THEN e.line -> 'components' ELSE '[]'::jsonb END) AS c (comp)
                WHERE jsonb_typeof(c.comp) <> 'object' OR jsonb_typeof(c.comp -> 'itemId') IS DISTINCT FROM 'number'
                   OR (c.comp ->> 'itemId')::numeric <= 0 OR (c.comp ->> 'itemId')::numeric <> trunc((c.comp ->> 'itemId')::numeric)
                   OR jsonb_typeof(c.comp -> 'makeText') NOT IN ('string', 'null') OR length(c.comp ->> 'makeText') > 300) THEN
        RAISE EXCEPTION 'Each component needs an item and a make text of up to 300 characters' USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
    SELECT string_agg(DISTINCT (c.comp ->> 'itemId'), ', ') INTO v_list
      FROM jsonb_array_elements(p_lines) AS e (line)
     CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(e.line -> 'components') = 'array' THEN e.line -> 'components' ELSE '[]'::jsonb END) AS c (comp)
     WHERE NOT EXISTS (SELECT 1 FROM package_lines pl WHERE pl.tenant_id = p_tenant_id AND pl.package_id = (e.line ->> 'packageId')::bigint
                          AND pl.item_id = (c.comp ->> 'itemId')::bigint);
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'Items % are not in the package of their line', v_list USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
END;
$$;
