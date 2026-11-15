-- Refuses a customer who already has an ACTIVE ticket (open or in progress). The message and the HINT carry the
-- existing ticket number, because the portal shows it to the customer ("you already have request TKT-2026-0001").
-- It is the HINT, not the DETAIL, on purpose: the Npgsql driver redacts DETAIL unless the connection string asks for error
-- details (which it must not), so a number in DETAIL would never reach the API.
-- This is the friendly check; uq_tickets_active_customer is the guarantee when two submissions arrive at the same moment,
-- and fn_create_ticket maps that race to this same answer by calling this procedure again.
--   NX409 rule conflict - the customer has an active ticket (COLUMN customerId; HINT is the ticket number)
CREATE OR REPLACE PROCEDURE sp_assert_no_active_ticket(p_tenant_id integer, p_customer_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_ticket_no varchar;
BEGIN
    SELECT t.ticket_no INTO v_ticket_no
      FROM tickets t
     WHERE t.tenant_id = p_tenant_id AND t.customer_id = p_customer_id AND t.status IN ('open', 'in_progress')
     LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'This customer already has an open ticket (%)', v_ticket_no
            USING ERRCODE = 'NX409', COLUMN = 'customerId', HINT = v_ticket_no;
    END IF;
END;
$$;
