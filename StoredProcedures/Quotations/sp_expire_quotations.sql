-- Marks every SENT quotation whose valid_until is before today (business time zone) as expired, and returns how
-- many in p_expired_count. Only sent quotations expire: a draft is still being written and an approved one stays
-- convertible (owner decision). The API calls this before reading a list or a quotation, because Hangfire is not
-- part of the build; a daily job can call it later without any change. The audit rows record the system as the
-- one who changed them (changed_by NULL).
-- The UPDATE locks each row it changes and re-checks the status when it gets the lock, so a quotation approved a
-- moment earlier is left alone.
CREATE OR REPLACE PROCEDURE sp_expire_quotations(p_tenant_id integer, OUT p_expired_count integer)
LANGUAGE plpgsql AS $$
BEGIN
    WITH due AS (
        UPDATE quotations
           SET status = 'expired', decided_at = now(), updated_at = now()
         WHERE tenant_id = p_tenant_id AND status = 'sent' AND valid_until < fn_business_today(p_tenant_id)
        RETURNING quotation_id),
    logged AS (
        INSERT INTO quotation_status_log (tenant_id, quotation_id, from_status, to_status, changed_by, note)
        SELECT p_tenant_id, d.quotation_id, 'sent', 'expired', NULL, 'Valid-until date passed'
          FROM due d
        RETURNING 1)
    SELECT count(*)::integer INTO p_expired_count FROM logged;
END;
$$;
