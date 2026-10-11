-- Module 5 (Inventory): units, items, suppliers, purchases and the stock ledger. Re-runnable.
--
-- Stock rules the database enforces on its own (the API validates first, but nothing relies on that):
--   * current_stock can never be negative (ck_items_stock_not_negative). An Admin override is a later option.
--   * stock_movements is append-only: a trigger refuses UPDATE, DELETE and TRUNCATE, so the ledger cannot be
--     edited even by code that bypasses the functions. A mistake is corrected with an adjustment row.
--   * quantity is always positive; signed_quantity carries the effect on stock (in = +, out = -, adjust = either).
--     The ledger reconciles with SUM(signed_quantity) per item = items.current_stock (see vw_item_stock_check).
--   * An adjustment must carry a note.
-- Custom SQLSTATEs used by the functions in StoredProcedures/Inventory (the API maps both to 409):
--   NX409 rule conflict (inactive item or supplier), NX411 insufficient stock.

CREATE TABLE IF NOT EXISTS units (
    unit_id     integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id   integer      NOT NULL,
    unit_code   varchar(10)  NOT NULL,
    unit_name   varchar(50)  NOT NULL,
    sort_order  integer      NOT NULL DEFAULT 0,
    is_active   boolean      NOT NULL DEFAULT true,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_units_tenant_code UNIQUE (tenant_id, unit_code)
);

CREATE TABLE IF NOT EXISTS items (
    item_id        bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id      integer       NOT NULL,
    item_code      varchar(30)   NOT NULL,
    item_name      varchar(150)  NOT NULL,
    unit           varchar(10)   NOT NULL,
    cost_price     numeric(12,2) NOT NULL DEFAULT 0,
    selling_price  numeric(12,2) NOT NULL DEFAULT 0,
    reorder_level  numeric(12,3) NOT NULL DEFAULT 0,   -- 0 means "no low-stock alert"
    current_stock  numeric(12,3) NOT NULL DEFAULT 0,   -- running total, changed only with a ledger row
    is_active      boolean       NOT NULL DEFAULT true,
    created_at     timestamptz   NOT NULL DEFAULT now(),
    updated_at     timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_items_tenant_code UNIQUE (tenant_id, item_code),
    CONSTRAINT fk_items_unit FOREIGN KEY (tenant_id, unit) REFERENCES units (tenant_id, unit_code),
    CONSTRAINT ck_items_code CHECK (item_code ~ '^[A-Z0-9][A-Z0-9._/-]*$'),
    CONSTRAINT ck_items_prices CHECK (cost_price >= 0 AND selling_price >= 0),
    CONSTRAINT ck_items_reorder_level CHECK (reorder_level >= 0),
    CONSTRAINT ck_items_stock_not_negative CHECK (current_stock >= 0)
);

CREATE INDEX IF NOT EXISTS ix_items_unit ON items (tenant_id, unit);

CREATE TABLE IF NOT EXISTS suppliers (
    supplier_id    bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id      integer      NOT NULL,
    supplier_name  varchar(150) NOT NULL,
    mobile         varchar(15),
    address        varchar(500),
    is_active      boolean      NOT NULL DEFAULT true,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    updated_at     timestamptz  NOT NULL DEFAULT now(),
    -- Same stored form as customers: ten digits, first digit 6-9. Optional for a supplier.
    CONSTRAINT ck_suppliers_mobile CHECK (mobile IS NULL OR mobile ~ '^[6-9][0-9]{9}$')
);

-- One supplier per name, ignoring case, so the same supplier is not entered twice.
CREATE UNIQUE INDEX IF NOT EXISTS uq_suppliers_tenant_name ON suppliers (tenant_id, lower(supplier_name));

CREATE TABLE IF NOT EXISTS purchases (
    purchase_id     bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id       integer       NOT NULL,
    purchase_no     varchar(30)   NOT NULL,              -- from fn_next_document_no, prefix PUR
    supplier_id     bigint        REFERENCES suppliers (supplier_id),
    purchase_date   date          NOT NULL,
    reference_text  varchar(100),                        -- the supplier's invoice number, for example
    total_amount    numeric(14,2) NOT NULL DEFAULT 0,
    created_by      integer       NOT NULL,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    updated_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_purchases_tenant_no UNIQUE (tenant_id, purchase_no),
    CONSTRAINT ck_purchases_total CHECK (total_amount >= 0)
);

CREATE INDEX IF NOT EXISTS ix_purchases_supplier_id ON purchases (supplier_id);
CREATE INDEX IF NOT EXISTS ix_purchases_date ON purchases (tenant_id, purchase_date DESC);

CREATE TABLE IF NOT EXISTS purchase_lines (
    purchase_line_id  bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id         integer       NOT NULL,
    purchase_id       bigint        NOT NULL REFERENCES purchases (purchase_id),
    item_id           bigint        NOT NULL REFERENCES items (item_id),
    quantity          numeric(12,3) NOT NULL,
    unit_cost         numeric(12,2) NOT NULL,
    line_total        numeric(14,2) NOT NULL,
    created_at        timestamptz   NOT NULL DEFAULT now(),
    -- An item appears once per purchase (the API rejects a duplicate; this is the safety net).
    CONSTRAINT uq_purchase_lines_purchase_item UNIQUE (purchase_id, item_id),
    CONSTRAINT ck_purchase_lines_quantity CHECK (quantity > 0),
    CONSTRAINT ck_purchase_lines_cost CHECK (unit_cost >= 0)
);

CREATE INDEX IF NOT EXISTS ix_purchase_lines_item_id ON purchase_lines (item_id);

CREATE TABLE IF NOT EXISTS stock_movements (
    movement_id      bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id        integer       NOT NULL,
    item_id          bigint        NOT NULL REFERENCES items (item_id),
    movement_type    varchar(10)   NOT NULL,
    quantity         numeric(12,3) NOT NULL,                 -- always positive
    signed_quantity  numeric(12,3) NOT NULL,                 -- the effect on current_stock
    unit_cost        numeric(12,2) NOT NULL DEFAULT 0,       -- purchase cost, or the item's cost price for out/adjust
    reference_type   varchar(15)   NOT NULL,
    reference_id     bigint,                                 -- purchase id, order id; null for adjustments
    note             varchar(250),
    created_by       integer       NOT NULL,
    created_at       timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT ck_stock_movements_type CHECK (movement_type IN ('in', 'out', 'adjust')),
    CONSTRAINT ck_stock_movements_reference CHECK (reference_type IN ('purchase', 'order', 'adjustment')),
    CONSTRAINT ck_stock_movements_quantity CHECK (quantity > 0 AND quantity = abs(signed_quantity)),
    CONSTRAINT ck_stock_movements_direction CHECK (
        (movement_type = 'in'  AND signed_quantity > 0) OR
        (movement_type = 'out' AND signed_quantity < 0) OR
        (movement_type = 'adjust')),
    CONSTRAINT ck_stock_movements_adjust CHECK (
        (movement_type = 'adjust') = (reference_type = 'adjustment')),
    CONSTRAINT ck_stock_movements_adjust_note CHECK (
        movement_type <> 'adjust' OR length(btrim(coalesce(note, ''))) > 0)
);

CREATE INDEX IF NOT EXISTS ix_stock_movements_item_created ON stock_movements (item_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_stock_movements_tenant_created ON stock_movements (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_stock_movements_reference ON stock_movements (reference_type, reference_id);

-- Append-only ledger. The trigger function lives in this script (not a function file) because the table needs
-- it at creation time and it never changes.
CREATE OR REPLACE FUNCTION fn_block_stock_movement_change()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'stock_movements is append-only: correct a mistake with an adjustment'
        USING ERRCODE = 'NX409';
END;
$$;

DROP TRIGGER IF EXISTS trg_stock_movements_no_change ON stock_movements;
CREATE TRIGGER trg_stock_movements_no_change
    BEFORE UPDATE OR DELETE ON stock_movements
    FOR EACH ROW EXECUTE FUNCTION fn_block_stock_movement_change();

DROP TRIGGER IF EXISTS trg_stock_movements_no_truncate ON stock_movements;
CREATE TRIGGER trg_stock_movements_no_truncate
    BEFORE TRUNCATE ON stock_movements
    FOR EACH STATEMENT EXECUTE FUNCTION fn_block_stock_movement_change();

-- Reporting read: one row per item with the ledger total next to the running stock. difference must be 0.
CREATE OR REPLACE VIEW vw_item_stock_check AS
SELECT i.tenant_id, i.item_id, i.item_code, i.current_stock,
       COALESCE(m.ledger_total, 0) AS ledger_total,
       i.current_stock - COALESCE(m.ledger_total, 0) AS difference
  FROM items i
  LEFT JOIN (SELECT sm.item_id, SUM(sm.signed_quantity) AS ledger_total
               FROM stock_movements sm
              GROUP BY sm.item_id) m ON m.item_id = i.item_id;

-- Units are master data. Adding one is an INSERT for now (a units admin screen is an Open item).
DO $$
DECLARE
    c_tenant_id CONSTANT integer := 1;   -- single-tenant for now; matches Tenant:DefaultId
BEGIN
    INSERT INTO units (tenant_id, unit_code, unit_name, sort_order)
    VALUES (c_tenant_id, 'nos',  'Numbers',  10),
           (c_tenant_id, 'm',    'Metre',    20),
           (c_tenant_id, 'kg',   'Kilogram', 30),
           (c_tenant_id, 'ltr',  'Litre',    40),
           (c_tenant_id, 'pack', 'Pack',     50),
           (c_tenant_id, 'box',  'Box',      60),
           (c_tenant_id, 'set',  'Set',      70),
           (c_tenant_id, 'pair', 'Pair',     80),
           (c_tenant_id, 'roll', 'Roll',     90)
    ON CONFLICT (tenant_id, unit_code) DO NOTHING;

    -- The time zone that "a date" means for the stock ledger filters and for "not in the future".
    INSERT INTO app_settings (tenant_id, setting_key, setting_value)
    VALUES (c_tenant_id, 'business_time_zone', 'Asia/Kolkata')
    ON CONFLICT (tenant_id, setting_key) DO NOTHING;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('10_inventory_schema.sql')
ON CONFLICT DO NOTHING;
