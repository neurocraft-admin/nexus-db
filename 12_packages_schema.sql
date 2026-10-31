-- Module 4 (Packages): a package is a reusable bundle of stock items sold at one typed-in price. Re-runnable.
-- Schema only: the resource, permissions and menu are in 13_packages_menu.sql.
--
--   * package_price is the selling price of the whole package, typed by the user and tax-inclusive. There is no
--     GST column, rate or tax split anywhere (owner decision, 2026-10-17). It must be above 0; a price below the
--     component cost is a warning for the person, never a block.
--   * A line is a stock item and a quantity (up to 3 decimals, for cable lengths). Item name, unit, cost, selling
--     price and stock are read live from items, so there is one source of truth. Labour is not a package line.
--   * Component cost is never stored as a live figure: vw_package_summary computes it from the current item cost
--     prices as the sum of round(quantity x cost_price, 2), half away from zero (the same rule as purchases).
--     component_cost_at_save records that figure when the package was last saved, so the screen can say "the
--     cost has risen by X since this price was set". Old quotations copy their own price and are never affected.
--   * Availability only reads items.current_stock. Packages never reserve or deduct stock; stock leaves only
--     through order fulfilment (sp_stock_out), where the strict no-negative-stock block applies.

CREATE TABLE IF NOT EXISTS packages (
    package_id              bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id               integer       NOT NULL,
    package_code            varchar(30)   NOT NULL,
    package_name            varchar(150)  NOT NULL,
    description             varchar(1000),
    package_price           numeric(12,2) NOT NULL,
    component_cost_at_save  numeric(14,2) NOT NULL DEFAULT 0,
    is_active               boolean       NOT NULL DEFAULT true,
    created_at              timestamptz   NOT NULL DEFAULT now(),
    updated_at              timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_packages_tenant_code UNIQUE (tenant_id, package_code),
    CONSTRAINT ck_packages_code CHECK (package_code ~ '^[A-Z0-9][A-Z0-9._/-]*$'),
    CONSTRAINT ck_packages_price CHECK (package_price > 0)
);

CREATE TABLE IF NOT EXISTS package_lines (
    package_line_id  bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id        integer       NOT NULL,
    package_id       bigint        NOT NULL REFERENCES packages (package_id),
    item_id          bigint        NOT NULL REFERENCES items (item_id),
    quantity         numeric(12,3) NOT NULL,
    sort_order       integer       NOT NULL,
    created_at       timestamptz   NOT NULL DEFAULT now(),
    -- An item appears once per package (the API rejects a duplicate; this is the safety net). The unique index
    -- also serves the package_id foreign key.
    CONSTRAINT uq_package_lines_package_item UNIQUE (package_id, item_id),
    CONSTRAINT ck_package_lines_quantity CHECK (quantity > 0)
);

CREATE INDEX IF NOT EXISTS ix_package_lines_item_id ON package_lines (item_id);

-- One row per package with the figures every screen needs. Reads go through this view.
--   component_cost / component_selling_total: sum of round(quantity x price, 2) over the lines, live
--   has_inactive_component:                   a component item has been deactivated ("Needs attention")
--   short_component_count:                    components whose stock is below the quantity for ONE set
--   no_cost_component_count:                  components whose cost price is still 0 (cost understated)
CREATE OR REPLACE VIEW vw_package_summary AS
SELECT p.tenant_id, p.package_id, p.package_code, p.package_name, p.description, p.package_price,
       p.component_cost_at_save, p.is_active, p.created_at, p.updated_at,
       COALESCE(c.component_count, 0)         AS component_count,
       COALESCE(c.component_cost, 0)          AS component_cost,
       COALESCE(c.component_selling_total, 0) AS component_selling_total,
       COALESCE(c.inactive_count, 0) > 0      AS has_inactive_component,
       COALESCE(c.short_count, 0)             AS short_component_count,
       COALESCE(c.no_cost_count, 0)           AS no_cost_component_count
  FROM packages p
  LEFT JOIN (SELECT pl.package_id,
                    count(*)                                         AS component_count,
                    sum(round(pl.quantity * i.cost_price, 2))        AS component_cost,
                    sum(round(pl.quantity * i.selling_price, 2))     AS component_selling_total,
                    count(*) FILTER (WHERE NOT i.is_active)          AS inactive_count,
                    count(*) FILTER (WHERE i.current_stock < pl.quantity) AS short_count,
                    count(*) FILTER (WHERE i.cost_price = 0)         AS no_cost_count
               FROM package_lines pl
               JOIN items i ON i.item_id = pl.item_id
              GROUP BY pl.package_id) c ON c.package_id = p.package_id;

INSERT INTO deployment_log (script_name) VALUES ('12_packages_schema.sql')
ON CONFLICT DO NOTHING;
