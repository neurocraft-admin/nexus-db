-- Creates (p_task_id NULL) or edits a task and returns its id. Only a NON-STAFF user may create or edit tasks: a staff caller
-- (p_visible_to is their id) is refused outright. p_assigned_to is used only when creating (reassigning is sp_assign_task). When a
-- ticket is given and no customer is, the customer is the ticket's. The link to a ticket is informational: finishing a task never
-- changes the ticket.
--   42501 insufficient privilege - the caller is a staff user
--   22023 / P0002 / NX409        - the field errors of sp_check_task_fields, the assignee rules, a finished task (see sp_update_task)
CREATE OR REPLACE FUNCTION fn_save_task(
    p_tenant_id integer, p_task_id bigint, p_task_type varchar, p_title varchar, p_description varchar, p_customer_id bigint,
    p_ticket_id bigint, p_assigned_to integer, p_scheduled_at timestamptz, p_visit_address varchar, p_latitude numeric,
    p_longitude numeric, p_user_id integer, p_visible_to integer)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_task_id  bigint := p_task_id;
    v_customer bigint;
BEGIN
    IF p_visible_to IS NOT NULL THEN
        RAISE EXCEPTION 'Only an administrator can create or edit tasks' USING ERRCODE = '42501';
    END IF;
    CALL sp_check_task_fields(p_tenant_id, p_task_type, p_title, p_description, p_customer_id, p_ticket_id, p_visit_address, p_latitude, p_longitude);
    v_customer := COALESCE(p_customer_id, (SELECT k.customer_id FROM tickets k WHERE k.ticket_id = p_ticket_id AND k.tenant_id = p_tenant_id));
    IF p_task_id IS NULL THEN
        CALL sp_insert_task(p_tenant_id, p_task_type, p_title, p_description, v_customer, p_ticket_id, p_assigned_to, p_scheduled_at,
                            p_visit_address, p_latitude, p_longitude, p_user_id, v_task_id);
    ELSE
        CALL sp_update_task(p_tenant_id, p_task_id, p_task_type, p_title, p_description, v_customer, p_ticket_id, p_scheduled_at,
                            p_visit_address, p_latitude, p_longitude);
    END IF;
    RETURN v_task_id;
END;
$$;
