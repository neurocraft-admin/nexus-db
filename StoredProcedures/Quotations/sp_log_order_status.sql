-- Appends one audit row for an order status change: who, what, when. Never updated or deleted.
CREATE OR REPLACE PROCEDURE sp_log_order_status(
    p_tenant_id integer, p_order_id bigint, p_from_status varchar, p_to_status varchar,
    p_changed_by integer, p_note varchar)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO order_status_log (tenant_id, order_id, from_status, to_status, changed_by, note)
    VALUES (p_tenant_id, p_order_id, p_from_status, p_to_status, p_changed_by, p_note);
END;
$$;
