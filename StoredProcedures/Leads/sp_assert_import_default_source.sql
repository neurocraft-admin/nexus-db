-- Checks the default source chosen for an import (NULL = none chosen) before anything is written: it must be a source of
-- this tenant that is still in use.
--   22023 invalid parameter - an unknown or retired source (COLUMN defaultSourceId)
CREATE OR REPLACE PROCEDURE sp_assert_import_default_source(p_tenant_id integer, p_default_source_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_default_source_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM lead_sources s WHERE s.lead_source_id = p_default_source_id AND s.tenant_id = p_tenant_id AND s.is_active) THEN
        RAISE EXCEPTION 'The default source is not a source in use' USING ERRCODE = '22023', COLUMN = 'defaultSourceId';
    END IF;
END;
$$;
