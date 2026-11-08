-- Reads the rows of an import and says, for each, what is wrong with it on its own (reason is NULL when nothing is).
-- The database validates every row itself: it does not trust that the caller checked, and the browser's reading of the
-- file is never relied on. p_rows is a JSON array, at most 1000 rows, of objects with the text of each cell:
--   {"name": "...", "mobile": "...", "email": "...", "address": "...", "source": "...", "expectedValue": "...",
--    "nextFollowUpDate": "yyyy-MM-dd", "notes": "..."}
-- row_number is the row's position in the array, starting at 1 (the API maps it back to a line of the file). The mobile
-- is reduced to the stored form here (fn_normalise_mobile) before anything is compared. A row with no source gets
-- p_default_source_id. Duplicates are NOT looked at here (see fn_check_import_rows).
--   22023 invalid parameter - no rows or more than 1000 (COLUMN rows)
CREATE OR REPLACE FUNCTION fn_parse_import_rows(p_tenant_id integer, p_rows jsonb, p_default_source_id integer)
RETURNS TABLE (row_number integer, lead_name text, mobile text, email text, address text, lead_source_id integer,
               expected_value numeric, next_follow_up_date date, notes text, reason text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    c_max_rows CONSTANT integer := 1000;
BEGIN
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND c_max_rows THEN
        RAISE EXCEPTION 'An import needs between 1 and % rows', c_max_rows USING ERRCODE = '22023', COLUMN = 'rows';
    END IF;
    RETURN QUERY
    WITH raw AS (
        SELECT e.ord::integer AS rn, NULLIF(btrim(e.item ->> 'name'), '') AS nm, fn_normalise_mobile(e.item ->> 'mobile') AS mob,
               NULLIF(btrim(e.item ->> 'email'), '') AS em, NULLIF(btrim(e.item ->> 'address'), '') AS ad,
               NULLIF(btrim(e.item ->> 'source'), '') AS src, NULLIF(btrim(e.item ->> 'expectedValue'), '') AS ev,
               NULLIF(btrim(e.item ->> 'nextFollowUpDate'), '') AS fd, NULLIF(btrim(e.item ->> 'notes'), '') AS nt
          FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS e (item, ord)),
    resolved AS (
        SELECT r.*, CASE WHEN r.src IS NULL THEN p_default_source_id ELSE s.lead_source_id END AS sid,
               s.is_active AS sactive, fn_try_numeric(r.ev) AS evn, fn_try_date(r.fd) AS fdd
          FROM raw r LEFT JOIN lead_sources s ON r.src IS NOT NULL AND s.tenant_id = p_tenant_id AND lower(s.source_name) = lower(r.src))
    SELECT x.rn, x.nm, x.mob, x.em, x.ad, x.sid, x.evn, x.fdd, x.nt,
           (CASE WHEN x.nm IS NULL THEN 'Name is required'
                 WHEN length(x.nm) > 150 THEN 'Name is longer than 150 characters'
                 WHEN x.mob !~ '^[6-9][0-9]{9}$' THEN 'Mobile must be a 10-digit number starting with 6, 7, 8 or 9'
                 WHEN x.em IS NOT NULL AND (length(x.em) > 150 OR x.em !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') THEN 'Email is not valid'
                 WHEN x.src IS NOT NULL AND x.sid IS NULL THEN 'Unknown source "' || left(x.src, 40) || '"'
                 WHEN x.sid IS NULL THEN 'No source: give one or choose a default'
                 WHEN x.sactive IS FALSE THEN 'Source "' || left(x.src, 40) || '" is no longer in use'
                 WHEN x.ev IS NOT NULL AND (x.evn IS NULL OR x.evn > 9999999999.99 OR x.evn <> round(x.evn, 2)) THEN 'Expected value must be a plain amount with at most 2 decimals'
                 WHEN x.fd IS NOT NULL AND x.fdd IS NULL THEN 'Follow-up date must be written yyyy-MM-dd'
                 WHEN length(x.ad) > 500 THEN 'Address is longer than 500 characters'
                 WHEN length(x.nt) > 2000 THEN 'Notes are longer than 2000 characters' END)::text
      FROM resolved x ORDER BY x.rn;
END;
$$;
