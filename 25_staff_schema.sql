-- Module 8 (Staff and tasks): staff profiles, tasks, their status history, and the view the staff dashboard reads.
-- Re-runnable. Schema and the view only: the resources, permissions and menu are in 26_staff_menu.sql.
--
--   * A staff member is a row in users (user_type 'staff') plus an OPTIONAL staff_profiles row. Whether a user is active is
--     users.is_active: the profile has no flag of its own, so there is one source of truth.
--   * A task is always assigned to one user (assigned_to). Only an active staff-type user whose role can see "My work" may be
--     given one (checked by sp_assert_task_assignee). Statuses: assigned -> in_progress -> done; assigned or in_progress ->
--     cancelled. done and cancelled are final. A task that is done carries its completion note and time.
--   * task_status_history is append-only (triggers below). One row is either a status change, or (assigned_to set, old and new
--     status the same) a reassignment. The first row of a task has no old status and names the first assignee.
--   * Visit location is the task's own address and optional coordinates (both or neither): the customer record has no map
--     position. A task may point at a customer and/or a ticket; the link is informational (completing a task never changes a ticket).
--   * vw_staff_work lists, per user, their tasks and their assigned tickets in one shape. fn_get_my_work reads it.

CREATE TABLE IF NOT EXISTS staff_profiles (
    user_id        integer       PRIMARY KEY REFERENCES users (user_id),
    tenant_id      integer       NOT NULL,
    employee_code  varchar(30),
    designation    varchar(100),
    mobile_alt     varchar(15),
    joining_date   date,
    notes          varchar(500),
    created_at     timestamptz   NOT NULL DEFAULT now(),
    updated_at     timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT ck_staff_profiles_code CHECK (employee_code IS NULL OR btrim(employee_code) <> ''),
    CONSTRAINT ck_staff_profiles_mobile_alt CHECK (mobile_alt IS NULL OR mobile_alt ~ '^[6-9][0-9]{9}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_staff_profiles_tenant_code ON staff_profiles (tenant_id, lower(employee_code))
    WHERE employee_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS tasks (
    task_id          bigint         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id        integer        NOT NULL,
    task_no          varchar(30)    NOT NULL,                  -- from fn_next_document_no, prefix TSK (TSK-2026-0001)
    task_type        varchar(15)    NOT NULL,
    title            varchar(150)   NOT NULL,
    description      varchar(1000),
    customer_id      bigint         REFERENCES customers (customer_id),
    ticket_id        bigint         REFERENCES tickets (ticket_id),
    assigned_to      integer        NOT NULL REFERENCES users (user_id),
    scheduled_at     timestamptz,
    visit_address    varchar(500),
    latitude         numeric(9,6),
    longitude        numeric(9,6),
    status           varchar(15)    NOT NULL DEFAULT 'assigned',
    completion_note  varchar(500),
    completed_at     timestamptz,                              -- when it became done or cancelled
    created_by       integer        NOT NULL REFERENCES users (user_id),
    created_at       timestamptz    NOT NULL DEFAULT now(),
    updated_at       timestamptz    NOT NULL DEFAULT now(),
    CONSTRAINT uq_tasks_tenant_no UNIQUE (tenant_id, task_no),
    CONSTRAINT ck_tasks_type CHECK (task_type IN ('installation', 'site_visit', 'service', 'other')),
    CONSTRAINT ck_tasks_status CHECK (status IN ('assigned', 'in_progress', 'done', 'cancelled')),
    CONSTRAINT ck_tasks_title CHECK (btrim(title) <> ''),
    CONSTRAINT ck_tasks_position CHECK ((latitude IS NULL) = (longitude IS NULL)),
    CONSTRAINT ck_tasks_latitude CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_tasks_longitude CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    -- The finish stamps follow the status: done has its note and time, cancelled its time, an open task neither.
    CONSTRAINT ck_tasks_stamps CHECK (
        (status <> 'done' OR (completed_at IS NOT NULL AND completion_note IS NOT NULL AND btrim(completion_note) <> ''))
        AND (status <> 'cancelled' OR completed_at IS NOT NULL)
        AND (status IN ('done', 'cancelled') OR completed_at IS NULL)
        AND (status = 'done' OR completion_note IS NULL))
);

CREATE INDEX IF NOT EXISTS ix_tasks_customer_id ON tasks (customer_id);
CREATE INDEX IF NOT EXISTS ix_tasks_ticket_id ON tasks (ticket_id);
CREATE INDEX IF NOT EXISTS ix_tasks_assigned_to ON tasks (assigned_to, status);
CREATE INDEX IF NOT EXISTS ix_tasks_created_by ON tasks (created_by);
CREATE INDEX IF NOT EXISTS ix_tasks_tenant_scheduled ON tasks (tenant_id, scheduled_at);

CREATE TABLE IF NOT EXISTS task_status_history (
    history_id   bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id    integer      NOT NULL,
    task_id      bigint       NOT NULL REFERENCES tasks (task_id),
    old_status   varchar(15),
    new_status   varchar(15)  NOT NULL,
    assigned_to  integer      REFERENCES users (user_id),    -- who the task went to, on the first row and on a reassignment
    changed_by   integer      NOT NULL REFERENCES users (user_id),
    note         varchar(500),
    changed_at   timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_task_history_old CHECK (old_status IS NULL OR old_status IN ('assigned', 'in_progress', 'done', 'cancelled')),
    CONSTRAINT ck_task_history_new CHECK (new_status IN ('assigned', 'in_progress', 'done', 'cancelled')),
    CONSTRAINT ck_task_history_assignment CHECK (assigned_to IS NULL OR old_status IS NULL OR old_status = new_status)
);

CREATE INDEX IF NOT EXISTS ix_task_status_history_task_id ON task_status_history (task_id, history_id);
CREATE INDEX IF NOT EXISTS ix_task_status_history_assigned_to ON task_status_history (assigned_to);
CREATE INDEX IF NOT EXISTS ix_task_status_history_changed_by ON task_status_history (changed_by);

-- The history cannot be rewritten, even by the application's own database user.
CREATE OR REPLACE FUNCTION fn_block_task_history_change()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'task_status_history is append-only' USING ERRCODE = 'NX409';
END;
$$;

DROP TRIGGER IF EXISTS trg_task_status_history_no_change ON task_status_history;
CREATE TRIGGER trg_task_status_history_no_change
    BEFORE UPDATE OR DELETE ON task_status_history
    FOR EACH ROW EXECUTE FUNCTION fn_block_task_history_change();

DROP TRIGGER IF EXISTS trg_task_status_history_no_truncate ON task_status_history;
CREATE TRIGGER trg_task_status_history_no_truncate
    BEFORE TRUNCATE ON task_status_history
    FOR EACH STATEMENT EXECUTE FUNCTION fn_block_task_history_change();

-- One shape for everything a person has to do: their tasks and their assigned tickets (all statuses; fn_get_my_work decides
-- what is shown). finished_at is when a task became done or cancelled, or when a ticket was resolved (else closed).
CREATE OR REPLACE VIEW vw_staff_work AS
SELECT t.tenant_id, t.assigned_to AS user_id, 'task'::varchar AS work_kind, t.task_id AS work_id, t.task_no AS reference_no,
       t.title, t.task_type AS work_type, c.customer_name, c.mobile AS customer_mobile,
       COALESCE(t.visit_address, c.address) AS address, t.latitude, t.longitude, t.scheduled_at, t.status,
       t.completed_at AS finished_at, t.created_at
  FROM tasks t
  LEFT JOIN customers c ON c.customer_id = t.customer_id
UNION ALL
SELECT k.tenant_id, k.assigned_to, 'ticket'::varchar, k.ticket_id, k.ticket_no,
       COALESCE(it.issue_type_name, k.other_issue_text)::varchar, 'ticket'::varchar, c.customer_name, c.mobile, c.address,
       NULL::numeric(9,6), NULL::numeric(9,6), NULL::timestamptz, k.status,
       CASE WHEN k.status IN ('resolved', 'closed') THEN COALESCE(k.resolved_at, k.closed_at) END, k.created_at
  FROM tickets k
  JOIN customers c ON c.customer_id = k.customer_id
  LEFT JOIN issue_types it ON it.issue_type_id = k.issue_type_id
 WHERE k.assigned_to IS NOT NULL;

INSERT INTO deployment_log (script_name) VALUES ('25_staff_schema.sql')
ON CONFLICT DO NOTHING;
