-- Conventions that hold for every function in the database, whichever module wrote it. Run after every release.
-- No function or procedure body may use SELECT * (the rule: columns are always named, so a column added to a table or a
-- function never changes what a caller receives). Comment lines are ignored; count(*) is not a SELECT *.
DO $$
DECLARE
    v_name text;
BEGIN
    SELECT string_agg(DISTINCT p.proname, ', ' ORDER BY p.proname) INTO v_name
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prokind IN ('f', 'p')
       AND p.prolang IN (SELECT l.oid FROM pg_language l WHERE l.lanname IN ('sql', 'plpgsql'))
       AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'select\s+(distinct\s+)?(\w+\.)?\*';
    IF v_name IS NOT NULL THEN
        RAISE EXCEPTION 'These functions use SELECT *; name the columns: %', v_name;
    END IF;
END;
$$;
