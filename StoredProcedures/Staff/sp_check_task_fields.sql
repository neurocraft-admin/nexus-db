-- Checks everything fn_save_task is given, before anything is written; messages name the field (COLUMN) for the API.
--   22023 invalid parameter - an unknown type; no title or one over 150; a description over 1000; an address over 500; coordinates
--                             given singly or out of range; a ticket that belongs to another customer than the one chosen
--   P0002 not found         - unknown customer or ticket (COLUMN customerId, ticketId)
CREATE OR REPLACE PROCEDURE sp_check_task_fields(
    p_tenant_id integer, p_task_type varchar, p_title varchar, p_description varchar, p_customer_id bigint, p_ticket_id bigint,
    p_visit_address varchar, p_latitude numeric, p_longitude numeric)
LANGUAGE plpgsql AS $$
DECLARE
    c_title_max       CONSTANT integer := 150;
    c_description_max CONSTANT integer := 1000;
    c_address_max     CONSTANT integer := 500;
    v_ticket_customer bigint;
BEGIN
    IF p_task_type IS NULL OR p_task_type NOT IN ('installation', 'site_visit', 'service', 'other') THEN
        RAISE EXCEPTION 'Choose installation, site visit, service or other' USING ERRCODE = '22023', COLUMN = 'taskType';
    END IF;
    IF p_title IS NULL OR btrim(p_title) = '' OR length(btrim(p_title)) > c_title_max THEN
        RAISE EXCEPTION 'A task needs a title of up to % characters', c_title_max USING ERRCODE = '22023', COLUMN = 'title';
    END IF;
    IF length(btrim(COALESCE(p_description, ''))) > c_description_max THEN
        RAISE EXCEPTION 'The description can be up to % characters', c_description_max USING ERRCODE = '22023', COLUMN = 'description';
    END IF;
    IF length(btrim(COALESCE(p_visit_address, ''))) > c_address_max THEN
        RAISE EXCEPTION 'The address can be up to % characters', c_address_max USING ERRCODE = '22023', COLUMN = 'visitAddress';
    END IF;
    IF (p_latitude IS NULL) <> (p_longitude IS NULL) OR p_latitude NOT BETWEEN -90 AND 90 OR p_longitude NOT BETWEEN -180 AND 180 THEN
        RAISE EXCEPTION 'Give both the latitude (-90 to 90) and the longitude (-180 to 180), or neither' USING ERRCODE = '22023', COLUMN = 'latitude';
    END IF;
    IF p_customer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = p_customer_id AND c.tenant_id = p_tenant_id) THEN
        RAISE EXCEPTION 'Customer % not found', p_customer_id USING ERRCODE = 'P0002', COLUMN = 'customerId';
    END IF;
    IF p_ticket_id IS NOT NULL THEN
        SELECT k.customer_id INTO v_ticket_customer FROM tickets k WHERE k.ticket_id = p_ticket_id AND k.tenant_id = p_tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Ticket % not found', p_ticket_id USING ERRCODE = 'P0002', COLUMN = 'ticketId';
        END IF;
        IF p_customer_id IS NOT NULL AND p_customer_id <> v_ticket_customer THEN
            RAISE EXCEPTION 'That ticket belongs to another customer' USING ERRCODE = '22023', COLUMN = 'ticketId';
        END IF;
    END IF;
END;
$$;
