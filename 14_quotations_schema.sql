-- Module 3 (Quotations and orders): templates, quotations, their lines, orders and order lines. Re-runnable.
-- Schema only: the resources, permissions and menu are in 15_quotations_menu.sql, the letterhead settings in 16.
--
--   * Every amount is tax-inclusive. There is no GST column, rate or tax split anywhere (owner decision,
--     2026-10-17); a quotation prints the fixed note "Prices are inclusive of tax".
--   * A line stores its own description, unit and price, copied when the line is added. Changing an item or a
--     package later never changes an issued quotation or an order.
--   * Money rule (the same as purchases): line_total = round(quantity x unit_price, 2), half away from zero;
--     subtotal = the sum of the rounded line totals; total = subtotal - discount. The discount is one flat amount
--     on the quotation and never exceeds the subtotal. The CHECK constraints below are the safety net for the
--     arithmetic that sp_save_quotation does.
--   * A quotation belongs to a customer or a lead. lead_id has NO foreign key yet: the Lead module adds it.
--   * revision_of_id links "Duplicate as new draft" to the quotation it was copied from (the revision chain).
--   * orders.quotation_id is UNIQUE: one order per quotation, ever (a cancelled order does not free the
--     quotation). payment_mode stays empty until the order is fulfilled.
--   * Stock is never reserved by a quotation or an order. It leaves only in sp_fulfil_order, where the strict
--     no-negative-stock rule of sp_stock_out applies.
--   * The two status log tables are append-only audit rows: who, what, when. changed_by is NULL when the system
--     did it (expiry).

CREATE TABLE IF NOT EXISTS quotation_templates (
    template_id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id              integer       NOT NULL,
    template_name          varchar(150)  NOT NULL,
    description            varchar(1000),
    default_validity_days  integer       NOT NULL DEFAULT 30,
    terms_text             varchar(4000),
    is_active              boolean       NOT NULL DEFAULT true,
    created_at             timestamptz   NOT NULL DEFAULT now(),
    updated_at             timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT ck_quotation_templates_validity CHECK (default_validity_days BETWEEN 1 AND 365)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_quotation_templates_tenant_name
    ON quotation_templates (tenant_id, lower(template_name));

CREATE TABLE IF NOT EXISTS quotation_template_lines (
    template_line_id  bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id         integer       NOT NULL,
    template_id       bigint        NOT NULL REFERENCES quotation_templates (template_id),
    line_type         varchar(10)   NOT NULL,
    item_id           bigint        REFERENCES items (item_id),
    package_id        bigint        REFERENCES packages (package_id),
    description       varchar(250)  NOT NULL,
    unit              varchar(20)   NOT NULL,
    quantity          numeric(12,3) NOT NULL,
    unit_price        numeric(12,2) NOT NULL,
    sort_order        integer       NOT NULL,
    created_at        timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT ck_quotation_template_lines_type CHECK (
        (line_type = 'item'    AND item_id IS NOT NULL AND package_id IS NULL) OR
        (line_type = 'package' AND package_id IS NOT NULL AND item_id IS NULL) OR
        (line_type = 'custom'  AND item_id IS NULL AND package_id IS NULL)),
    CONSTRAINT ck_quotation_template_lines_quantity CHECK (quantity > 0),
    CONSTRAINT ck_quotation_template_lines_package_qty CHECK (
        line_type <> 'package' OR (quantity = trunc(quantity) AND quantity BETWEEN 1 AND 1000)),
    CONSTRAINT ck_quotation_template_lines_price CHECK (unit_price >= 0)
);

CREATE INDEX IF NOT EXISTS ix_quotation_template_lines_template_id ON quotation_template_lines (template_id);
CREATE INDEX IF NOT EXISTS ix_quotation_template_lines_item_id ON quotation_template_lines (item_id);
CREATE INDEX IF NOT EXISTS ix_quotation_template_lines_package_id ON quotation_template_lines (package_id);

CREATE TABLE IF NOT EXISTS quotations (
    quotation_id     bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id        integer       NOT NULL,
    quotation_no     varchar(30)   NOT NULL,              -- from fn_next_document_no, prefix QTN
    customer_id      bigint        REFERENCES customers (customer_id),
    lead_id          bigint,                              -- no foreign key until the Lead module exists
    template_id      bigint        REFERENCES quotation_templates (template_id),
    revision_of_id   bigint        REFERENCES quotations (quotation_id),
    status           varchar(10)   NOT NULL DEFAULT 'draft',
    quotation_date   date          NOT NULL,
    valid_until      date          NOT NULL,
    subtotal         numeric(14,2) NOT NULL DEFAULT 0,
    discount_amount  numeric(12,2) NOT NULL DEFAULT 0,
    total_amount     numeric(14,2) NOT NULL DEFAULT 0,
    terms_text       varchar(4000),
    notes            varchar(1000),
    created_by       integer       NOT NULL,
    sent_at          timestamptz,
    decided_at       timestamptz,
    created_at       timestamptz   NOT NULL DEFAULT now(),
    updated_at       timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_quotations_tenant_no UNIQUE (tenant_id, quotation_no),
    CONSTRAINT ck_quotations_status CHECK (status IN ('draft', 'sent', 'approved', 'rejected', 'expired', 'converted')),
    CONSTRAINT ck_quotations_party CHECK (customer_id IS NOT NULL OR lead_id IS NOT NULL),
    CONSTRAINT ck_quotations_dates CHECK (valid_until >= quotation_date),
    CONSTRAINT ck_quotations_totals CHECK (
        discount_amount >= 0 AND discount_amount <= subtotal AND total_amount = subtotal - discount_amount)
);

CREATE INDEX IF NOT EXISTS ix_quotations_customer_id ON quotations (customer_id);
CREATE INDEX IF NOT EXISTS ix_quotations_template_id ON quotations (template_id);
CREATE INDEX IF NOT EXISTS ix_quotations_revision_of_id ON quotations (revision_of_id);
CREATE INDEX IF NOT EXISTS ix_quotations_tenant_status ON quotations (tenant_id, status);

CREATE TABLE IF NOT EXISTS quotation_lines (
    quotation_line_id  bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id          integer       NOT NULL,
    quotation_id       bigint        NOT NULL REFERENCES quotations (quotation_id),
    line_type          varchar(10)   NOT NULL,
    item_id            bigint        REFERENCES items (item_id),
    package_id         bigint        REFERENCES packages (package_id),
    description        varchar(250)  NOT NULL,
    unit               varchar(20)   NOT NULL,
    quantity           numeric(12,3) NOT NULL,
    unit_price         numeric(12,2) NOT NULL,
    line_total         numeric(14,2) NOT NULL,
    sort_order         integer       NOT NULL,
    created_at         timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT ck_quotation_lines_type CHECK (
        (line_type = 'item'    AND item_id IS NOT NULL AND package_id IS NULL) OR
        (line_type = 'package' AND package_id IS NOT NULL AND item_id IS NULL) OR
        (line_type = 'custom'  AND item_id IS NULL AND package_id IS NULL)),
    CONSTRAINT ck_quotation_lines_quantity CHECK (quantity > 0),
    CONSTRAINT ck_quotation_lines_package_qty CHECK (
        line_type <> 'package' OR (quantity = trunc(quantity) AND quantity BETWEEN 1 AND 1000)),
    CONSTRAINT ck_quotation_lines_price CHECK (unit_price >= 0),
    CONSTRAINT ck_quotation_lines_total CHECK (line_total = round(quantity * unit_price, 2))
);

CREATE INDEX IF NOT EXISTS ix_quotation_lines_quotation_id ON quotation_lines (quotation_id);
CREATE INDEX IF NOT EXISTS ix_quotation_lines_item_id ON quotation_lines (item_id);
CREATE INDEX IF NOT EXISTS ix_quotation_lines_package_id ON quotation_lines (package_id);

CREATE TABLE IF NOT EXISTS quotation_status_log (
    log_id        bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id     integer      NOT NULL,
    quotation_id  bigint       NOT NULL REFERENCES quotations (quotation_id),
    from_status   varchar(10),
    to_status     varchar(10)  NOT NULL,
    changed_by    integer,
    changed_at    timestamptz  NOT NULL DEFAULT now(),
    note          varchar(250)
);

CREATE INDEX IF NOT EXISTS ix_quotation_status_log_quotation_id ON quotation_status_log (quotation_id);

CREATE TABLE IF NOT EXISTS orders (
    order_id      bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id     integer       NOT NULL,
    order_no      varchar(30)   NOT NULL,                 -- from fn_next_document_no, prefix ORD
    quotation_id  bigint        NOT NULL REFERENCES quotations (quotation_id),
    customer_id   bigint        NOT NULL REFERENCES customers (customer_id),
    status        varchar(10)   NOT NULL DEFAULT 'new',
    payment_mode  varchar(6),                             -- chosen when the order is fulfilled
    total_amount  numeric(14,2) NOT NULL,
    fulfilled_at  timestamptz,
    cancelled_at  timestamptz,
    created_by    integer       NOT NULL,
    created_at    timestamptz   NOT NULL DEFAULT now(),
    updated_at    timestamptz   NOT NULL DEFAULT now(),
    -- One order per quotation, ever. This is what makes a double-click on Convert safe; it also serves the
    -- quotation_id foreign key.
    CONSTRAINT uq_orders_quotation UNIQUE (quotation_id),
    CONSTRAINT uq_orders_tenant_no UNIQUE (tenant_id, order_no),
    CONSTRAINT ck_orders_status CHECK (status IN ('new', 'fulfilled', 'cancelled')),
    CONSTRAINT ck_orders_payment_mode CHECK (payment_mode IS NULL OR payment_mode IN ('paid', 'credit')),
    CONSTRAINT ck_orders_total CHECK (total_amount >= 0),
    CONSTRAINT ck_orders_fulfilled CHECK (status <> 'fulfilled' OR (payment_mode IS NOT NULL AND fulfilled_at IS NOT NULL)),
    CONSTRAINT ck_orders_cancelled CHECK (status <> 'cancelled' OR cancelled_at IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS ix_orders_customer_id ON orders (customer_id);
CREATE INDEX IF NOT EXISTS ix_orders_tenant_status ON orders (tenant_id, status);

CREATE TABLE IF NOT EXISTS order_lines (
    order_line_id  bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id      integer       NOT NULL,
    order_id       bigint        NOT NULL REFERENCES orders (order_id),
    line_type      varchar(10)   NOT NULL,
    item_id        bigint        REFERENCES items (item_id),
    package_id     bigint        REFERENCES packages (package_id),
    description    varchar(250)  NOT NULL,
    unit           varchar(20)   NOT NULL,
    quantity       numeric(12,3) NOT NULL,
    unit_price     numeric(12,2) NOT NULL,
    line_total     numeric(14,2) NOT NULL,
    sort_order     integer       NOT NULL,
    created_at     timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT ck_order_lines_type CHECK (
        (line_type = 'item'    AND item_id IS NOT NULL AND package_id IS NULL) OR
        (line_type = 'package' AND package_id IS NOT NULL AND item_id IS NULL) OR
        (line_type = 'custom'  AND item_id IS NULL AND package_id IS NULL)),
    CONSTRAINT ck_order_lines_quantity CHECK (quantity > 0),
    CONSTRAINT ck_order_lines_total CHECK (line_total = round(quantity * unit_price, 2))
);

CREATE INDEX IF NOT EXISTS ix_order_lines_order_id ON order_lines (order_id);
CREATE INDEX IF NOT EXISTS ix_order_lines_item_id ON order_lines (item_id);
CREATE INDEX IF NOT EXISTS ix_order_lines_package_id ON order_lines (package_id);

CREATE TABLE IF NOT EXISTS order_status_log (
    log_id      bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id   integer      NOT NULL,
    order_id    bigint       NOT NULL REFERENCES orders (order_id),
    from_status varchar(10),
    to_status   varchar(10)  NOT NULL,
    changed_by  integer,
    changed_at  timestamptz  NOT NULL DEFAULT now(),
    note        varchar(250)
);

CREATE INDEX IF NOT EXISTS ix_order_status_log_order_id ON order_status_log (order_id);

-- Both status logs are append-only, like the stock ledger: a trigger refuses UPDATE, DELETE and TRUNCATE, so the
-- history of who changed what and when cannot be rewritten, even by the application's own database user. The
-- trigger function lives in this script (not a function file) because the tables need it at creation time.
CREATE OR REPLACE FUNCTION fn_block_status_log_change()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% is append-only', TG_TABLE_NAME USING ERRCODE = 'NX409';
END;
$$;

DROP TRIGGER IF EXISTS trg_quotation_status_log_no_change ON quotation_status_log;
CREATE TRIGGER trg_quotation_status_log_no_change
    BEFORE UPDATE OR DELETE ON quotation_status_log
    FOR EACH ROW EXECUTE FUNCTION fn_block_status_log_change();

DROP TRIGGER IF EXISTS trg_quotation_status_log_no_truncate ON quotation_status_log;
CREATE TRIGGER trg_quotation_status_log_no_truncate
    BEFORE TRUNCATE ON quotation_status_log
    FOR EACH STATEMENT EXECUTE FUNCTION fn_block_status_log_change();

DROP TRIGGER IF EXISTS trg_order_status_log_no_change ON order_status_log;
CREATE TRIGGER trg_order_status_log_no_change
    BEFORE UPDATE OR DELETE ON order_status_log
    FOR EACH ROW EXECUTE FUNCTION fn_block_status_log_change();

DROP TRIGGER IF EXISTS trg_order_status_log_no_truncate ON order_status_log;
CREATE TRIGGER trg_order_status_log_no_truncate
    BEFORE TRUNCATE ON order_status_log
    FOR EACH STATEMENT EXECUTE FUNCTION fn_block_status_log_change();

INSERT INTO deployment_log (script_name) VALUES ('14_quotations_schema.sql')
ON CONFLICT DO NOTHING;
