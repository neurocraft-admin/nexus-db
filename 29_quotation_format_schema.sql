-- Quotation format (Deepu's model): what a quotation, a template and an order now carry. Re-runnable; nothing is dropped and no existing value changes
-- meaning. Script 30 adds the subsidy slabs, 31 the menu, 32 the company defaults.
--
--   items                      make_text: the default "make and warranty" text printed in the Make column of the technical proposal
--   subsidy_categories         master data: none, domestic, commercial (has_subsidy says whether a subsidy applies); rows are tenant data
--   quotation_templates        the document settings a quotation starts from: title, hero image, capacity, subsidy category, whether line
--                              prices are shown, cost-page notes, payment terms and terms and conditions (restricted HTML), plus a datasheet list
--   quotations                 the same settings per quotation, the subsidy figures (saved with the quotation, never recalculated after the
--                              fact), extra_charges_amount (the pass-through lines, e.g. KSEB, kept outside "customer payable" but inside the
--                              total) and company_snapshot (the company details frozen when the quotation is SENT; drafts read the live profile)
--   quotation_template_lines,  make_text and is_extra_charge (only a custom line can be an extra charge)
--   quotation_lines
--   quotation_line_components  a package line printed as its component items: copied from the package when the quotation is saved, with a
--                              make text that can be overridden per quotation (the package's own price is not shown on the proposal)
--   orders, order_lines        extra_charges_amount / is_extra_charge, copied from the quotation, so a report can leave pass-through fees out later
--   datasheets, template_datasheets, quotation_datasheets
--                              the datasheet PDF library (the file itself lives in the API's file folder; only its names are here) and the
--                              ordered list of datasheets merged after the technical proposal, per template and per quotation
-- The old plain-text terms (terms_text) are copied into terms_html as one paragraph per line the first time this runs; terms_text stays in
-- place and is still written by the old save path. Existing quotations and templates keep showing line prices (show_line_prices defaults true).
DO $$
DECLARE
    c_tenant_id CONSTANT integer := 1;   -- single-tenant for now; matches Tenant:DefaultId
BEGIN
    CREATE TABLE IF NOT EXISTS subsidy_categories (
        tenant_id      integer      NOT NULL,
        category_code  varchar(20)  NOT NULL,
        category_name  varchar(60)  NOT NULL,
        has_subsidy    boolean      NOT NULL,
        sort_order     integer      NOT NULL DEFAULT 0,
        is_active      boolean      NOT NULL DEFAULT true,
        PRIMARY KEY (tenant_id, category_code),
        CONSTRAINT ck_subsidy_categories_code CHECK (category_code ~ '^[a-z][a-z_]*$'),
        CONSTRAINT ck_subsidy_categories_name CHECK (btrim(category_name) <> '')
    );
    INSERT INTO subsidy_categories (tenant_id, category_code, category_name, has_subsidy, sort_order)
    VALUES (c_tenant_id, 'none', 'No subsidy', false, 10),
           (c_tenant_id, 'domestic', 'Domestic', true, 20),
           (c_tenant_id, 'commercial', 'Commercial', false, 30)
    ON CONFLICT (tenant_id, category_code) DO NOTHING;
END;
$$;

ALTER TABLE items ADD COLUMN IF NOT EXISTS make_text varchar(300);

ALTER TABLE quotation_templates
    ADD COLUMN IF NOT EXISTS document_title      varchar(250),
    ADD COLUMN IF NOT EXISTS hero_file_name      varchar(100),
    ADD COLUMN IF NOT EXISTS hero_content_type   varchar(20),
    ADD COLUMN IF NOT EXISTS capacity_kw         numeric(6,2),
    ADD COLUMN IF NOT EXISTS subsidy_category    varchar(20)   NOT NULL DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS show_line_prices    boolean       NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS cost_notes          varchar(1000),
    ADD COLUMN IF NOT EXISTS payment_terms_html  varchar(20000),
    ADD COLUMN IF NOT EXISTS terms_html          varchar(20000);

ALTER TABLE quotations
    ADD COLUMN IF NOT EXISTS document_title      varchar(250),
    ADD COLUMN IF NOT EXISTS hero_file_name      varchar(100),
    ADD COLUMN IF NOT EXISTS hero_content_type   varchar(20),
    ADD COLUMN IF NOT EXISTS capacity_kw         numeric(6,2),
    ADD COLUMN IF NOT EXISTS subsidy_category    varchar(20)   NOT NULL DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS subsidy_amount      numeric(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS subsidy_overridden  boolean       NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS show_line_prices    boolean       NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS cost_notes          varchar(1000),
    ADD COLUMN IF NOT EXISTS payment_terms_html  varchar(20000),
    ADD COLUMN IF NOT EXISTS terms_html          varchar(20000),
    ADD COLUMN IF NOT EXISTS extra_charges_amount numeric(14,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS company_snapshot    jsonb;

ALTER TABLE quotation_template_lines
    ADD COLUMN IF NOT EXISTS make_text        varchar(300),
    ADD COLUMN IF NOT EXISTS is_extra_charge  boolean NOT NULL DEFAULT false;
ALTER TABLE quotation_lines
    ADD COLUMN IF NOT EXISTS make_text        varchar(300),
    ADD COLUMN IF NOT EXISTS is_extra_charge  boolean NOT NULL DEFAULT false;
ALTER TABLE order_lines ADD COLUMN IF NOT EXISTS is_extra_charge boolean NOT NULL DEFAULT false;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS extra_charges_amount numeric(14,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS quotation_line_components (
    component_id       bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id          integer       NOT NULL,
    quotation_line_id  bigint        NOT NULL REFERENCES quotation_lines (quotation_line_id),
    item_id            bigint        NOT NULL REFERENCES items (item_id),
    description        varchar(250)  NOT NULL,
    unit               varchar(20)   NOT NULL,
    quantity           numeric(12,3) NOT NULL,             -- per ONE set of the package; the proposal multiplies by the line's quantity
    make_text          varchar(300),
    sort_order         integer       NOT NULL,
    created_at         timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_quotation_line_components UNIQUE (quotation_line_id, item_id),
    CONSTRAINT ck_quotation_line_components_quantity CHECK (quantity > 0)
);
CREATE INDEX IF NOT EXISTS ix_quotation_line_components_item_id ON quotation_line_components (item_id);

CREATE TABLE IF NOT EXISTS datasheets (
    datasheet_id        bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id           integer       NOT NULL,
    datasheet_name      varchar(150)  NOT NULL,
    stored_file_name    varchar(100)  NOT NULL,            -- the name the API gave the PDF on disk; never reused, never edited
    original_file_name  varchar(255)  NOT NULL,
    size_bytes          integer       NOT NULL,
    is_active           boolean       NOT NULL DEFAULT true,
    created_by          integer       NOT NULL REFERENCES users (user_id),
    created_at          timestamptz   NOT NULL DEFAULT now(),
    updated_at          timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_datasheets_stored_file UNIQUE (stored_file_name),
    CONSTRAINT ck_datasheets_name CHECK (btrim(datasheet_name) <> ''),
    CONSTRAINT ck_datasheets_size CHECK (size_bytes > 0)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_datasheets_active_name ON datasheets (tenant_id, lower(datasheet_name)) WHERE is_active;
CREATE INDEX IF NOT EXISTS ix_datasheets_created_by ON datasheets (created_by);

CREATE TABLE IF NOT EXISTS template_datasheets (
    tenant_id     integer NOT NULL,
    template_id   bigint  NOT NULL REFERENCES quotation_templates (template_id),
    datasheet_id  bigint  NOT NULL REFERENCES datasheets (datasheet_id),
    sort_order    integer NOT NULL,
    PRIMARY KEY (template_id, datasheet_id),
    CONSTRAINT uq_template_datasheets_order UNIQUE (template_id, sort_order)
);
CREATE INDEX IF NOT EXISTS ix_template_datasheets_datasheet_id ON template_datasheets (datasheet_id);

CREATE TABLE IF NOT EXISTS quotation_datasheets (
    tenant_id     integer NOT NULL,
    quotation_id  bigint  NOT NULL REFERENCES quotations (quotation_id),
    datasheet_id  bigint  NOT NULL REFERENCES datasheets (datasheet_id),
    sort_order    integer NOT NULL,
    PRIMARY KEY (quotation_id, datasheet_id),
    CONSTRAINT uq_quotation_datasheets_order UNIQUE (quotation_id, sort_order)
);
CREATE INDEX IF NOT EXISTS ix_quotation_datasheets_datasheet_id ON quotation_datasheets (datasheet_id);

CREATE INDEX IF NOT EXISTS ix_quotation_templates_subsidy_category ON quotation_templates (tenant_id, subsidy_category);
CREATE INDEX IF NOT EXISTS ix_quotations_subsidy_category ON quotations (tenant_id, subsidy_category);

-- Constraints are added only when missing, so the script can run again.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT c.t, c.n, c.d FROM (VALUES
        ('quotation_templates', 'ck_quotation_templates_capacity', 'CHECK (capacity_kw IS NULL OR capacity_kw > 0)'),
        ('quotation_templates', 'fk_quotation_templates_subsidy_category',
         'FOREIGN KEY (tenant_id, subsidy_category) REFERENCES subsidy_categories (tenant_id, category_code)'),
        ('quotations', 'ck_quotations_capacity', 'CHECK (capacity_kw IS NULL OR capacity_kw > 0)'),
        ('quotations', 'fk_quotations_subsidy_category',
         'FOREIGN KEY (tenant_id, subsidy_category) REFERENCES subsidy_categories (tenant_id, category_code)'),
        ('quotations', 'ck_quotations_extra_charges', 'CHECK (extra_charges_amount >= 0 AND extra_charges_amount <= subtotal)'),
        ('quotations', 'ck_quotations_discount_payable', 'CHECK (discount_amount <= subtotal - extra_charges_amount)'),
        ('quotations', 'ck_quotations_subsidy_amount',
         'CHECK (subsidy_amount >= 0 AND subsidy_amount <= subtotal - extra_charges_amount - discount_amount)'),
        ('quotations', 'ck_quotations_snapshot_not_draft', 'CHECK (status <> ''draft'' OR company_snapshot IS NULL)'),
        ('quotation_template_lines', 'ck_quotation_template_lines_extra', 'CHECK (NOT is_extra_charge OR line_type = ''custom'')'),
        ('quotation_lines', 'ck_quotation_lines_extra', 'CHECK (NOT is_extra_charge OR line_type = ''custom'')'),
        ('order_lines', 'ck_order_lines_extra', 'CHECK (NOT is_extra_charge OR line_type = ''custom'')'),
        ('orders', 'ck_orders_extra_charges', 'CHECK (extra_charges_amount >= 0 AND extra_charges_amount <= total_amount)')
    ) AS c (t, n, d)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conname = r.n AND k.conrelid = to_regclass(r.t)) THEN
            EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I %s', r.t, r.n, r.d);
        END IF;
    END LOOP;
END;
$$;

-- Old plain-text terms become paragraphs (one per non-empty line, text escaped) the first time only: a row that already has terms_html is left alone.
UPDATE quotations q
   SET terms_html = x.html
  FROM (SELECT t.quotation_id,
               string_agg('<p>' || replace(replace(replace(btrim(l.line), '&', '&amp;'), '<', '&lt;'), '>', '&gt;') || '</p>', '' ORDER BY l.n) AS html
          FROM quotations t
         CROSS JOIN LATERAL regexp_split_to_table(t.terms_text, E'\r?\n') WITH ORDINALITY AS l (line, n)
         WHERE t.terms_html IS NULL AND t.terms_text IS NOT NULL AND btrim(l.line) <> ''
         GROUP BY t.quotation_id) x
 WHERE q.quotation_id = x.quotation_id AND q.terms_html IS NULL;
UPDATE quotation_templates q
   SET terms_html = x.html
  FROM (SELECT t.template_id,
               string_agg('<p>' || replace(replace(replace(btrim(l.line), '&', '&amp;'), '<', '&lt;'), '>', '&gt;') || '</p>', '' ORDER BY l.n) AS html
          FROM quotation_templates t
         CROSS JOIN LATERAL regexp_split_to_table(t.terms_text, E'\r?\n') WITH ORDINALITY AS l (line, n)
         WHERE t.terms_html IS NULL AND t.terms_text IS NOT NULL AND btrim(l.line) <> ''
         GROUP BY t.template_id) x
 WHERE q.template_id = x.template_id AND q.terms_html IS NULL;

-- Existing package lines get their component rows from the package as it is now (what the quotation would print today), once.
INSERT INTO quotation_line_components (tenant_id, quotation_line_id, item_id, description, unit, quantity, make_text, sort_order)
SELECT l.tenant_id, l.quotation_line_id, pl.item_id, i.item_name, i.unit, pl.quantity, i.make_text, pl.sort_order
  FROM quotation_lines l
  JOIN package_lines pl ON pl.package_id = l.package_id AND pl.tenant_id = l.tenant_id
  JOIN items i ON i.item_id = pl.item_id
 WHERE l.line_type = 'package'
   AND NOT EXISTS (SELECT 1 FROM quotation_line_components c WHERE c.quotation_line_id = l.quotation_line_id)
ON CONFLICT (quotation_line_id, item_id) DO NOTHING;

INSERT INTO deployment_log (script_name) VALUES ('29_quotation_format_schema.sql')
ON CONFLICT DO NOTHING;
