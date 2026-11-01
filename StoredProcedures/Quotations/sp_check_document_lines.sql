-- Validates the SHAPE of the lines of a quotation or a template. p_lines is a JSON array of
-- {"lineType": "item"|"package"|"custom", "itemId": 1, "packageId": null, "description": "", "unit": "",
--  "quantity": 2.5, "unitPrice": 100}. description, unit and unitPrice are optional for item and package lines
-- (they default from the item or package); a custom line needs a description and a price. Item quantities have up
-- to 3 decimals (the item rule); a package quantity is a whole number from 1 to 1000. The same item may appear on
-- several lines. Each RAISE names the request field with COLUMN. Whether the items and packages exist and are
-- active is sp_check_document_references.
--   22023 invalid parameter - no lines, more than 200, or a line that breaks a rule above
CREATE OR REPLACE PROCEDURE sp_check_document_lines(p_lines jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    c_max_lines CONSTANT integer := 200;
    c_max_text  CONSTANT integer := 250;
    c_max_unit  CONSTANT integer := 20;
    c_max_sets  CONSTANT integer := 1000;
BEGIN
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) NOT BETWEEN 1 AND c_max_lines THEN
        RAISE EXCEPTION 'A quotation needs between 1 and % lines', c_max_lines USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_to_recordset(p_lines) AS l ("lineType" text, "itemId" bigint, "packageId" bigint,
                                                        description text, unit text, quantity numeric, "unitPrice" numeric)
         WHERE l."lineType" IS NULL OR l."lineType" NOT IN ('item', 'package', 'custom')
            OR l.quantity IS NULL OR l.quantity <= 0 OR l.quantity <> round(l.quantity, 3)
            OR l."unitPrice" < 0 OR l."unitPrice" <> round(l."unitPrice", 2)
            OR length(l.description) > c_max_text OR length(l.unit) > c_max_unit
            OR (l."lineType" = 'item' AND (l."itemId" IS NULL OR l."itemId" <= 0 OR l."packageId" IS NOT NULL))
            OR (l."lineType" = 'package' AND (l."packageId" IS NULL OR l."packageId" <= 0 OR l."itemId" IS NOT NULL
                                              OR l.quantity <> trunc(l.quantity) OR l.quantity > c_max_sets))
            OR (l."lineType" = 'custom' AND (l."itemId" IS NOT NULL OR l."packageId" IS NOT NULL
                                             OR btrim(COALESCE(l.description, '')) = '' OR l."unitPrice" IS NULL))) THEN
        RAISE EXCEPTION 'Each line needs a type, a quantity above zero (a whole number of 1 to % for a package), a price of 0 or more with at most 2 decimals, and a description for a custom line', c_max_sets
            USING ERRCODE = '22023', COLUMN = 'lines';
    END IF;
END;
$$;
