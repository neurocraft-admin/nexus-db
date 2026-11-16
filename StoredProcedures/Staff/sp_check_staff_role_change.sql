-- A staff member who still has open tasks cannot be moved to a role that cannot see My work: they would be holding work they can no
-- longer see. Moving to the same role, or to one that can see it, is always fine.
--   NX409 rule conflict - the new role has no access to My work and the person has open tasks (COLUMN roleId)
CREATE OR REPLACE PROCEDURE sp_check_staff_role_change(p_tenant_id integer, p_user_id integer, p_new_role_id integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_old_role integer;
    v_open     bigint;
BEGIN
    SELECT u.role_id INTO v_old_role FROM users u WHERE u.user_id = p_user_id AND u.tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND OR v_old_role = p_new_role_id OR fn_role_can_receive_work(p_tenant_id, p_new_role_id) THEN
        RETURN;
    END IF;
    SELECT count(*) INTO v_open FROM tasks t
     WHERE t.tenant_id = p_tenant_id AND t.assigned_to = p_user_id AND t.status IN ('assigned', 'in_progress');
    IF v_open > 0 THEN
        RAISE EXCEPTION 'This person has % open task(s) and the new role cannot see My work. Reassign the tasks first.', v_open
            USING ERRCODE = 'NX409', COLUMN = 'roleId';
    END IF;
END;
$$;
