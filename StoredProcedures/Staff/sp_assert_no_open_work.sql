-- Refuses to take a person out of service while they still have open work: tasks that are assigned or in progress, and tickets
-- that are open or in progress. Their work must be reassigned first, or it would be stranded on someone who cannot sign in.
-- Called by fn_set_user_active (so the Users screen and the Staff screen are held to the same rule).
--   NX409 rule conflict - the person has open work (COLUMN isActive); the message gives the counts
CREATE OR REPLACE PROCEDURE sp_assert_no_open_work(p_tenant_id integer, p_user_id integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_tasks   bigint;
    v_tickets bigint;
    v_name    varchar;
BEGIN
    SELECT count(*) INTO v_tasks FROM tasks t
     WHERE t.tenant_id = p_tenant_id AND t.assigned_to = p_user_id AND t.status IN ('assigned', 'in_progress');
    SELECT count(*) INTO v_tickets FROM tickets k
     WHERE k.tenant_id = p_tenant_id AND k.assigned_to = p_user_id AND k.status IN ('open', 'in_progress');
    IF v_tasks > 0 OR v_tickets > 0 THEN
        SELECT u.full_name INTO v_name FROM users u WHERE u.user_id = p_user_id AND u.tenant_id = p_tenant_id;
        RAISE EXCEPTION '% still has % open task(s) and % open ticket(s). Reassign them first.', COALESCE(v_name, 'This person'), v_tasks, v_tickets
            USING ERRCODE = 'NX409', COLUMN = 'isActive';
    END IF;
END;
$$;
