-- Module 6: customers and their credit ledger. Re-runnable; same shape as the reference pattern in CLAUDE.md.
-- credit_balance is the amount the customer owes. It can go negative: that is an advance payment.
-- The unique key (tenant_id, mobile) also covers deactivated customers, so a number stays reserved after
-- deactivation; fn_save_customer says so with a clear message instead of a bare constraint error.
-- mobile has ONE stored form: ten digits, first digit 6-9 (an Indian mobile number). The API strips spaces,
-- dashes and a +91 or 0 prefix before it gets here; this CHECK is the safety net for anything that does not
-- go through the API. Added to 08 before it was applied anywhere real, so 08 was edited rather than adding a script.

CREATE TABLE IF NOT EXISTS customers (
    customer_id     bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id       integer       NOT NULL,
    customer_name   varchar(150)  NOT NULL,
    mobile          varchar(15)   NOT NULL,
    address         varchar(500),
    credit_balance  numeric(12,2) NOT NULL DEFAULT 0,   -- amount the customer owes
    is_active       boolean       NOT NULL DEFAULT true,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    updated_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_customers_tenant_mobile UNIQUE (tenant_id, mobile),
    CONSTRAINT ck_customers_mobile CHECK (mobile ~ '^[6-9][0-9]{9}$')
);

-- A database that already ran an earlier version of this script has the table but not the CHECK. Existing
-- rows must already be in the stored form; if one is not, this fails loudly and names the constraint.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_customers_mobile') THEN
        ALTER TABLE customers ADD CONSTRAINT ck_customers_mobile CHECK (mobile ~ '^[6-9][0-9]{9}$');
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS customer_credit_ledgers (
    ledger_id    bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id    integer       NOT NULL,
    customer_id  bigint        NOT NULL REFERENCES customers (customer_id),
    entry_type   varchar(10)   NOT NULL CHECK (entry_type IN ('charge', 'payment')),
    amount       numeric(12,2) NOT NULL CHECK (amount > 0),
    note         varchar(250),
    created_by   integer       NOT NULL,
    created_at   timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_customer_credit_ledgers_customer_id
    ON customer_credit_ledgers (customer_id);

INSERT INTO deployment_log (script_name) VALUES ('08_customers_schema.sql')
ON CONFLICT DO NOTHING;
