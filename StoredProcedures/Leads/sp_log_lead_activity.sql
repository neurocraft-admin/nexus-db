-- Appends one row to a lead's history: who, what, when. The old and new values are the readable text (a status name,
-- a person's name, a date), never an id. Never updated or deleted (a trigger refuses it).
CREATE OR REPLACE PROCEDURE sp_log_lead_activity(
    p_tenant_id integer, p_lead_id bigint, p_activity_type varchar, p_old_value varchar, p_new_value varchar,
    p_note varchar, p_user_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO lead_activities (tenant_id, lead_id, activity_type, old_value, new_value, note, created_by)
    VALUES (p_tenant_id, p_lead_id, p_activity_type, left(p_old_value, 250), left(p_new_value, 250), p_note, p_user_id);
END;
$$;
