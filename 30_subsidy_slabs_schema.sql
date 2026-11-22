-- Subsidy slabs: the government subsidy is set per capacity range, so the amount is a table the administrator edits, never a constant in code.
-- A slab is a flat amount for a category and a capacity range: capacity_from_kw is INCLUDED and capacity_to_kw is NOT included (a half-open range
-- [from, to), so two slabs can never share a capacity); no upper bound ("3 kW and above") is capacity_to_kw NULL. Both bounds may be fractional.
-- Slabs are never deleted (a slab that no longer applies is switched off). No rows are seeded: the owner enters them on the Subsidy slabs screen.
-- A quotation keeps the subsidy it was saved with, so changing a slab never changes an existing quotation.
-- Overlap between two ACTIVE slabs of the same category is refused by sp_save_subsidy_slab (under a lock, so two saves cannot both pass).
-- Re-runnable.
CREATE TABLE IF NOT EXISTS subsidy_slabs (
    slab_id           bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id         integer       NOT NULL,
    category_code     varchar(20)   NOT NULL,
    capacity_from_kw  numeric(6,2)  NOT NULL,
    capacity_to_kw    numeric(6,2),
    amount            numeric(12,2) NOT NULL,
    is_active         boolean       NOT NULL DEFAULT true,
    updated_by        integer       REFERENCES users (user_id),
    created_at        timestamptz   NOT NULL DEFAULT now(),
    updated_at        timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT fk_subsidy_slabs_category FOREIGN KEY (tenant_id, category_code) REFERENCES subsidy_categories (tenant_id, category_code),
    CONSTRAINT ck_subsidy_slabs_range CHECK (capacity_from_kw >= 0 AND (capacity_to_kw IS NULL OR capacity_to_kw > capacity_from_kw)),
    CONSTRAINT ck_subsidy_slabs_amount CHECK (amount >= 0)
);
-- Two active slabs of a category cannot start at the same capacity (the rest of the overlap rule is in sp_save_subsidy_slab).
CREATE UNIQUE INDEX IF NOT EXISTS uq_subsidy_slabs_active_from ON subsidy_slabs (tenant_id, category_code, capacity_from_kw) WHERE is_active;
CREATE INDEX IF NOT EXISTS ix_subsidy_slabs_category ON subsidy_slabs (tenant_id, category_code);
CREATE INDEX IF NOT EXISTS ix_subsidy_slabs_updated_by ON subsidy_slabs (updated_by);

INSERT INTO deployment_log (script_name) VALUES ('30_subsidy_slabs_schema.sql')
ON CONFLICT DO NOTHING;
