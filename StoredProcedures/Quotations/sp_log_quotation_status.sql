-- Appends one audit row for a quotation status change: who, what, when. p_changed_by is NULL when the system did
-- it (expiry). Never updated or deleted.
CREATE OR REPLACE PROCEDURE sp_log_quotation_status(
    p_tenant_id integer, p_quotation_id bigint, p_from_status varchar, p_to_status varchar,
    p_changed_by integer, p_note varchar)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO quotation_status_log (tenant_id, quotation_id, from_status, to_status, changed_by, note)
    VALUES (p_tenant_id, p_quotation_id, p_from_status, p_to_status, p_changed_by, p_note);
END;
$$;
