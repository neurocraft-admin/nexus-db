-- A share as a percentage with one decimal: won out of created. 0 when nothing was created (no division by zero).
CREATE OR REPLACE FUNCTION fn_conversion_pct(p_part bigint, p_whole bigint)
RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN COALESCE(p_whole, 0) = 0 THEN 0 ELSE round(COALESCE(p_part, 0) * 100.0 / p_whole, 1) END;
$$;
