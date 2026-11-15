-- Checks that a ticket can be given to this user: the user exists in this tenant and is active. Staff and admin users
-- can both be given tickets.
--   P0002 not found     - unknown user (COLUMN assignedTo)
--   NX409 rule conflict - a deactivated user (COLUMN assignedTo)
CREATE OR REPLACE PROCEDURE sp_assert_ticket_assignee(p_tenant_id integer, p_user_id integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_active boolean;
BEGIN
    SELECT u.is_active INTO v_active FROM users u WHERE u.user_id = p_user_id AND u.tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found', p_user_id USING ERRCODE = 'P0002', COLUMN = 'assignedTo';
    END IF;
    IF NOT v_active THEN
        RAISE EXCEPTION 'User % is deactivated and cannot be given tickets', p_user_id USING ERRCODE = 'NX409', COLUMN = 'assignedTo';
    END IF;
END;
$$;
