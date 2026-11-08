-- Module 1 (Leads): sources, pipeline statuses, leads, their history, and import batches. Also adds the foreign key
-- on quotations.lead_id that Module 3 deferred. Re-runnable.
-- Schema, seeds and the quotation constraint only: the resources, permissions and menu are in 18_leads_menu.sql.
--
--   * Sources and statuses are TABLES, never code. A source or status added by script appears with no code change.
--     lead_sources.source_code is a stable machine code (for example 'facebook') so a later integration can map
--     "this lead came from Meta" to a row without a schema change; leads.external_ref (the platform's own lead id,
--     unique per source) and leads.source_detail (a campaign or form name) are there for the same reason and are
--     empty for every lead entered by hand. Nothing in NEXUS reads them yet.
--   * A lead is OPEN when it is active and not closed (Won or Lost). is_closed is kept by the functions from the
--     status flags (is_won / is_lost) because a partial unique index cannot look at another table. The unique index
--     uq_leads_open_mobile is what makes "one open lead per mobile number" hold even when two people save at once.
--   * The stored mobile has ONE form, the same as customers: ten digits, first digit 6-9 (ck_leads_mobile).
--   * lead_activities is the lead's history (who, what, when) and is append-only, like the other audit tables.
--   * A lead assigned to a staff user is visible to that user only; every read and write function takes
--     p_visible_to (the staff user's id, or NULL for an admin) and treats a lead outside it as not found.

CREATE TABLE IF NOT EXISTS lead_sources (
    lead_source_id  integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id       integer      NOT NULL,
    source_name     varchar(100) NOT NULL,
    source_code     varchar(30),
    sort_order      integer      NOT NULL DEFAULT 0,
    is_active       boolean      NOT NULL DEFAULT true,
    created_at      timestamptz  NOT NULL DEFAULT now(),
    updated_at      timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_lead_sources_code CHECK (source_code IS NULL OR source_code ~ '^[a-z][a-z0-9_]*$')
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_lead_sources_tenant_name ON lead_sources (tenant_id, lower(source_name));
CREATE UNIQUE INDEX IF NOT EXISTS uq_lead_sources_tenant_code ON lead_sources (tenant_id, source_code) WHERE source_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS lead_statuses (
    lead_status_id  integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id       integer      NOT NULL,
    status_name     varchar(50)  NOT NULL,
    sort_order      integer      NOT NULL DEFAULT 0,
    is_won          boolean      NOT NULL DEFAULT false,
    is_lost         boolean      NOT NULL DEFAULT false,
    is_active       boolean      NOT NULL DEFAULT true,
    created_at      timestamptz  NOT NULL DEFAULT now(),
    updated_at      timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_lead_statuses_not_both CHECK (NOT (is_won AND is_lost))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_lead_statuses_tenant_name ON lead_statuses (tenant_id, lower(status_name));

CREATE TABLE IF NOT EXISTS lead_import_batches (
    batch_id           bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id          integer      NOT NULL,
    file_name          varchar(255) NOT NULL,
    total_rows         integer      NOT NULL DEFAULT 0,
    created_rows       integer      NOT NULL DEFAULT 0,
    rejected_rows      integer      NOT NULL DEFAULT 0,
    default_source_id  integer      REFERENCES lead_sources (lead_source_id),
    assigned_to        integer      REFERENCES users (user_id),
    created_by         integer      NOT NULL,
    created_at         timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_lead_import_batches_default_source_id ON lead_import_batches (default_source_id);
CREATE INDEX IF NOT EXISTS ix_lead_import_batches_assigned_to ON lead_import_batches (assigned_to);

CREATE TABLE IF NOT EXISTS leads (
    lead_id                bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id              integer       NOT NULL,
    lead_no                varchar(30)   NOT NULL,                -- from fn_next_document_no, prefix LD
    lead_name              varchar(150)  NOT NULL,
    mobile                 varchar(15)   NOT NULL,
    email                  varchar(150),
    address                varchar(500),
    lead_source_id         integer       NOT NULL REFERENCES lead_sources (lead_source_id),
    lead_status_id         integer       NOT NULL REFERENCES lead_statuses (lead_status_id),
    assigned_to            integer       REFERENCES users (user_id),
    expected_value         numeric(12,2),
    next_follow_up_date    date,
    notes                  varchar(2000),
    lost_reason            varchar(250),
    converted_customer_id  bigint        REFERENCES customers (customer_id),
    converted_at           timestamptz,
    external_ref           varchar(100),                          -- the platform's own lead id (Meta later); NULL for manual leads
    source_detail          varchar(250),                          -- a campaign or form name; NULL for manual leads
    import_batch_id        bigint        REFERENCES lead_import_batches (batch_id),
    created_by             integer       NOT NULL,
    is_active              boolean       NOT NULL DEFAULT true,
    is_closed              boolean       NOT NULL DEFAULT false,
    closed_at              timestamptz,
    created_at             timestamptz   NOT NULL DEFAULT now(),
    updated_at             timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_leads_tenant_no UNIQUE (tenant_id, lead_no),
    CONSTRAINT ck_leads_mobile CHECK (mobile ~ '^[6-9][0-9]{9}$'),
    CONSTRAINT ck_leads_name CHECK (btrim(lead_name) <> ''),
    CONSTRAINT ck_leads_expected_value CHECK (expected_value IS NULL OR expected_value >= 0),
    CONSTRAINT ck_leads_converted_is_closed CHECK (converted_customer_id IS NULL OR is_closed)
);

-- One OPEN lead per mobile number, even under concurrent saves. Open = active and not closed (Won or Lost).
CREATE UNIQUE INDEX IF NOT EXISTS uq_leads_open_mobile ON leads (tenant_id, mobile) WHERE is_active AND NOT is_closed;
-- A platform's own lead id arrives once per source (the Meta import will rely on this to be safe to repeat).
CREATE UNIQUE INDEX IF NOT EXISTS uq_leads_source_external_ref ON leads (tenant_id, lead_source_id, external_ref) WHERE external_ref IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_leads_lead_source_id ON leads (lead_source_id);
CREATE INDEX IF NOT EXISTS ix_leads_lead_status_id ON leads (lead_status_id);
CREATE INDEX IF NOT EXISTS ix_leads_assigned_to ON leads (assigned_to);
CREATE INDEX IF NOT EXISTS ix_leads_converted_customer_id ON leads (converted_customer_id);
CREATE INDEX IF NOT EXISTS ix_leads_import_batch_id ON leads (import_batch_id);
CREATE INDEX IF NOT EXISTS ix_leads_tenant_mobile ON leads (tenant_id, mobile);
CREATE INDEX IF NOT EXISTS ix_leads_follow_up ON leads (tenant_id, next_follow_up_date) WHERE is_active AND NOT is_closed;

CREATE TABLE IF NOT EXISTS lead_activities (
    activity_id    bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id      integer       NOT NULL,
    lead_id        bigint        NOT NULL REFERENCES leads (lead_id),
    activity_type  varchar(20)   NOT NULL,
    old_value      varchar(250),
    new_value      varchar(250),
    note           varchar(2000),
    created_by     integer       NOT NULL,
    created_at     timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT ck_lead_activities_type CHECK (activity_type IN
        ('created', 'status_change', 'assigned', 'note', 'follow_up', 'converted', 'deactivated', 'reactivated'))
);

CREATE INDEX IF NOT EXISTS ix_lead_activities_lead_id ON lead_activities (lead_id, activity_id);

-- The history cannot be rewritten, even by the application's own database user.
CREATE OR REPLACE FUNCTION fn_block_lead_activity_change()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'lead_activities is append-only' USING ERRCODE = 'NX409';
END;
$$;

DROP TRIGGER IF EXISTS trg_lead_activities_no_change ON lead_activities;
CREATE TRIGGER trg_lead_activities_no_change
    BEFORE UPDATE OR DELETE ON lead_activities
    FOR EACH ROW EXECUTE FUNCTION fn_block_lead_activity_change();

DROP TRIGGER IF EXISTS trg_lead_activities_no_truncate ON lead_activities;
CREATE TRIGGER trg_lead_activities_no_truncate
    BEFORE TRUNCATE ON lead_activities
    FOR EACH STATEMENT EXECUTE FUNCTION fn_block_lead_activity_change();

-- Master data. A value added later by script appears in the dropdowns without a code change. Won and Lost are
-- flags, not names: the code never looks for the word "Won". The pipeline is New, Contacted, Qualified,
-- Negotiation, then Won (only through Convert) or Lost (needs a reason).
DO $$
DECLARE
    c_tenant_id CONSTANT integer := 1;   -- single-tenant for now; matches Tenant:DefaultId
BEGIN
    INSERT INTO lead_sources (tenant_id, source_name, source_code, sort_order)
    VALUES (c_tenant_id, 'Facebook', 'facebook', 10), (c_tenant_id, 'Instagram', 'instagram', 20),
           (c_tenant_id, 'Walk-in', 'walk_in', 30), (c_tenant_id, 'Referral', 'referral', 40),
           (c_tenant_id, 'Phone', 'phone', 50)
    ON CONFLICT (tenant_id, lower(source_name)) DO NOTHING;

    INSERT INTO lead_statuses (tenant_id, status_name, sort_order, is_won, is_lost)
    VALUES (c_tenant_id, 'New', 10, false, false), (c_tenant_id, 'Contacted', 20, false, false),
           (c_tenant_id, 'Qualified', 30, false, false), (c_tenant_id, 'Negotiation', 40, false, false),
           (c_tenant_id, 'Won', 50, true, false), (c_tenant_id, 'Lost', 60, false, true)
    ON CONFLICT (tenant_id, lower(status_name)) DO NOTHING;
END;
$$;

-- The constraint Module 3 left for this module: a quotation's lead must be a real lead. Written to be safe to run
-- twice. If any quotation already points at a lead that does not exist the script STOPS and says how many, because
-- adding the constraint over bad data would fail anyway and a half-applied script is worse than a clear message.
DO $$
DECLARE
    v_orphans integer;
BEGIN
    SELECT count(*) INTO v_orphans FROM quotations q
     WHERE q.lead_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM leads l WHERE l.lead_id = q.lead_id);
    IF v_orphans > 0 THEN
        RAISE EXCEPTION '% quotation(s) point at a lead that does not exist (quotations.lead_id). Fix or clear them, then run 17_leads_schema.sql again: SELECT quotation_id, quotation_no, lead_id FROM quotations q WHERE lead_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM leads l WHERE l.lead_id = q.lead_id)', v_orphans;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_quotations_lead') THEN
        ALTER TABLE quotations ADD CONSTRAINT fk_quotations_lead FOREIGN KEY (lead_id) REFERENCES leads (lead_id);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS ix_quotations_lead_id ON quotations (lead_id);

INSERT INTO deployment_log (script_name) VALUES ('17_leads_schema.sql')
ON CONFLICT DO NOTHING;
