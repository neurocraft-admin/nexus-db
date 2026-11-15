-- Checks that a task can be given to this user: they exist in this tenant, are active, are a STAFF-type user, and their role can
-- see "My work" (otherwise they would be given something they cannot see).
--   P0002 not found     - unknown user (COLUMN assignedTo)
--   NX409 rule conflict - deactivated, not a staff user, or a role with no access to My work (COLUMN assignedTo)
CREATE OR REPLACE PROCEDURE sp_assert_task_assignee(p_tenant_id integer, p_user_id integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_user record;
BEGIN
    SELECT u.is_active, u.user_type, u.role_id INTO v_user FROM users u WHERE u.user_id = p_user_id AND u.tenant_id = p_tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found', p_user_id USING ERRCODE = 'P0002', COLUMN = 'assignedTo';
    END IF;
    IF NOT v_user.is_active THEN
        RAISE EXCEPTION 'That person is deactivated and cannot be given tasks' USING ERRCODE = 'NX409', COLUMN = 'assignedTo';
    END IF;
    IF v_user.user_type <> 'staff' THEN
        RAISE EXCEPTION 'Tasks can only be given to staff users' USING ERRCODE = 'NX409', COLUMN = 'assignedTo';
    END IF;
    IF NOT fn_role_can_receive_work(p_tenant_id, v_user.role_id) THEN
        RAISE EXCEPTION 'That person''s role has no access to My work, so they could not see a task given to them'
            USING ERRCODE = 'NX409', COLUMN = 'assignedTo';
    END IF;
END;
$$;
