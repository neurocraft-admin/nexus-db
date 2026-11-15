-- Module 7 (Service tickets and the support portal): issue types, tickets, their status history and attachments.
-- Re-runnable. Schema and seeds only: the resources, permissions and menu are in 23_tickets_menu.sql.
--
--   * A ticket is ACTIVE while it is 'open' or 'in_progress'. A customer can have only ONE active ticket, and the
--     partial unique index uq_tickets_active_customer is what makes that hold when two submissions arrive at the same
--     moment (the friendly check in fn_create_ticket comes first; the index is the guarantee).
--   * Statuses: open -> in_progress -> resolved -> closed. Reopen is resolved -> in_progress and nothing else;
--     closed is final; open -> closed is allowed with a note. The rules live in sp_check_ticket_status_move.
--   * ticket_status_history is append-only (triggers below). One row says either "the status changed" (old status
--     differs from new) or "the ticket was assigned" (assigned_to is set; old and new status are the same). The first
--     row of a ticket has no old status. changed_by is NULL for a ticket raised on the portal.
--   * A ticket raised on the portal has no created_by (the customer has no login); a ticket raised by staff has one.
--   * Exactly one of issue_type_id or other_issue_text is set. "Other" is therefore NOT an issue type row: the portal
--     adds an "Other" option to the dropdown that sends free text.
--   * Attachments are files kept outside the database (Tickets:AttachmentPath); the row keeps the random stored name
--     and the original name as text only. The portal accepts one file per ticket; that is an API rule, not a constraint.

CREATE TABLE IF NOT EXISTS issue_types (
    issue_type_id    integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id        integer      NOT NULL,
    issue_type_name  varchar(100) NOT NULL,
    sort_order       integer      NOT NULL DEFAULT 0,
    is_active        boolean      NOT NULL DEFAULT true,
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_issue_types_name CHECK (btrim(issue_type_name) <> '')
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_issue_types_tenant_name ON issue_types (tenant_id, lower(issue_type_name));

CREATE TABLE IF NOT EXISTS tickets (
    ticket_id         bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id         integer       NOT NULL,
    ticket_no         varchar(30)   NOT NULL,                -- from fn_next_document_no, prefix TKT (TKT-2026-0001)
    customer_id       bigint        NOT NULL REFERENCES customers (customer_id),
    issue_type_id     integer       REFERENCES issue_types (issue_type_id),
    other_issue_text  varchar(100),
    description       varchar(500)  NOT NULL,
    status            varchar(15)   NOT NULL DEFAULT 'open',
    source            varchar(10)   NOT NULL,
    assigned_to       integer       REFERENCES users (user_id),
    resolved_at       timestamptz,
    closed_at         timestamptz,
    created_by        integer       REFERENCES users (user_id),
    created_at        timestamptz   NOT NULL DEFAULT now(),
    updated_at        timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_tickets_tenant_no UNIQUE (tenant_id, ticket_no),
    CONSTRAINT ck_tickets_status CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    CONSTRAINT ck_tickets_source CHECK (source IN ('portal', 'internal')),
    CONSTRAINT ck_tickets_issue CHECK ((issue_type_id IS NOT NULL) <> (other_issue_text IS NOT NULL)),
    CONSTRAINT ck_tickets_other_text CHECK (other_issue_text IS NULL OR btrim(other_issue_text) <> ''),
    CONSTRAINT ck_tickets_description CHECK (btrim(description) <> ''),
    CONSTRAINT ck_tickets_creator CHECK ((source = 'portal') = (created_by IS NULL)),
    -- The time stamps follow the status: resolved_at while resolved (and kept once closed after a resolve),
    -- closed_at only once closed. A reopened ticket has no resolved_at.
    CONSTRAINT ck_tickets_stamps CHECK (
        (status <> 'resolved' OR resolved_at IS NOT NULL)
        AND (status <> 'closed' OR closed_at IS NOT NULL)
        AND (status IN ('resolved', 'closed') OR resolved_at IS NULL)
        AND (status = 'closed' OR closed_at IS NULL))
);

-- One active ticket per customer, even when two people submit at the same moment.
CREATE UNIQUE INDEX IF NOT EXISTS uq_tickets_active_customer ON tickets (tenant_id, customer_id)
    WHERE status IN ('open', 'in_progress');

CREATE INDEX IF NOT EXISTS ix_tickets_customer_id ON tickets (customer_id);
CREATE INDEX IF NOT EXISTS ix_tickets_issue_type_id ON tickets (issue_type_id);
CREATE INDEX IF NOT EXISTS ix_tickets_assigned_to ON tickets (assigned_to);
CREATE INDEX IF NOT EXISTS ix_tickets_created_by ON tickets (created_by);
CREATE INDEX IF NOT EXISTS ix_tickets_tenant_status ON tickets (tenant_id, status);

CREATE TABLE IF NOT EXISTS ticket_status_history (
    history_id   bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id    integer      NOT NULL,
    ticket_id    bigint       NOT NULL REFERENCES tickets (ticket_id),
    old_status   varchar(15),
    new_status   varchar(15)  NOT NULL,
    assigned_to  integer      REFERENCES users (user_id),   -- set only on an assignment row: who the ticket went to
    changed_by   integer      REFERENCES users (user_id),
    note         varchar(500),
    changed_at   timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_ticket_history_old CHECK (old_status IS NULL OR old_status IN ('open', 'in_progress', 'resolved', 'closed')),
    CONSTRAINT ck_ticket_history_new CHECK (new_status IN ('open', 'in_progress', 'resolved', 'closed')),
    CONSTRAINT ck_ticket_history_assignment CHECK (assigned_to IS NULL OR old_status = new_status)
);

CREATE INDEX IF NOT EXISTS ix_ticket_status_history_ticket_id ON ticket_status_history (ticket_id, history_id);
CREATE INDEX IF NOT EXISTS ix_ticket_status_history_assigned_to ON ticket_status_history (assigned_to);
CREATE INDEX IF NOT EXISTS ix_ticket_status_history_changed_by ON ticket_status_history (changed_by);

CREATE TABLE IF NOT EXISTS ticket_attachments (
    attachment_id  bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id      integer       NOT NULL,
    ticket_id      bigint        NOT NULL REFERENCES tickets (ticket_id),
    original_name  varchar(255)  NOT NULL,                 -- shown as text only, never used in a path
    stored_name    varchar(100)  NOT NULL,                 -- random name of the file under Tickets:AttachmentPath
    content_type   varchar(30)   NOT NULL,
    size_bytes     integer       NOT NULL,
    uploaded_at    timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_ticket_attachments_stored_name UNIQUE (stored_name),
    CONSTRAINT ck_ticket_attachments_type CHECK (content_type IN ('application/pdf', 'image/jpeg', 'image/png')),
    CONSTRAINT ck_ticket_attachments_size CHECK (size_bytes > 0 AND size_bytes <= 5242880),   -- 5 MB
    CONSTRAINT ck_ticket_attachments_name CHECK (btrim(original_name) <> '' AND btrim(stored_name) <> '')
);

CREATE INDEX IF NOT EXISTS ix_ticket_attachments_ticket_id ON ticket_attachments (ticket_id);

-- The history cannot be rewritten, even by the application's own database user.
CREATE OR REPLACE FUNCTION fn_block_ticket_history_change()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'ticket_status_history is append-only' USING ERRCODE = 'NX409';
END;
$$;

DROP TRIGGER IF EXISTS trg_ticket_status_history_no_change ON ticket_status_history;
CREATE TRIGGER trg_ticket_status_history_no_change
    BEFORE UPDATE OR DELETE ON ticket_status_history
    FOR EACH ROW EXECUTE FUNCTION fn_block_ticket_history_change();

DROP TRIGGER IF EXISTS trg_ticket_status_history_no_truncate ON ticket_status_history;
CREATE TRIGGER trg_ticket_status_history_no_truncate
    BEFORE TRUNCATE ON ticket_status_history
    FOR EACH STATEMENT EXECUTE FUNCTION fn_block_ticket_history_change();

-- Master data: an admin edits these on the Issue types screen; a value added later appears in the dropdowns with no
-- code change. There is deliberately no "Other" row (see the note at the top).
DO $$
DECLARE
    c_tenant_id CONSTANT integer := 1;   -- single-tenant for now; matches Tenant:DefaultId
BEGIN
    INSERT INTO issue_types (tenant_id, issue_type_name, sort_order)
    VALUES (c_tenant_id, 'Not working', 10),
           (c_tenant_id, 'Low generation', 20),
           (c_tenant_id, 'Inverter fault', 30),
           (c_tenant_id, 'Net metering', 40),
           (c_tenant_id, 'Cleaning request', 50)
    ON CONFLICT (tenant_id, lower(issue_type_name)) DO NOTHING;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('22_tickets_schema.sql')
ON CONFLICT DO NOTHING;
