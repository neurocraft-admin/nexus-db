-- Company profile: who the business is, in one row per tenant (names, logo, address, contacts, tax ids, bank details and
-- the default quotation texts). It replaces the five ad hoc letterhead rows in app_settings (script 16), so the app can
-- be handed to another business, or serve many, without code changes. Re-runnable.
--
--   * Every column except tenant_id is optional: a new tenant starts with an empty profile.
--   * GSTIN, PAN and the state code are printed on the quotation PDF when filled. They are labels only: amounts stay
--     tax-inclusive and nothing is calculated from them (amendment to the 2026-10-17 "no GST anywhere" decision).
--   * The logo is a FILE under Company:LogoPath; the table stores only its random stored name and its type.
--   * The old app_settings rows are copied once and left in place; a later script (24) drops them after the PDF has been
--     confirmed on the new table. An existing profile row is never overwritten by a re-run.
CREATE TABLE IF NOT EXISTS company_profile (
    company_profile_id    integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id             integer       NOT NULL,
    legal_name            varchar(200),
    display_name          varchar(150),
    tagline               varchar(200),
    logo_file_name        varchar(100),
    logo_content_type     varchar(20),
    address_line1         varchar(200),
    address_line2         varchar(200),
    city                  varchar(100),
    state_name            varchar(100),
    pincode               varchar(6),
    phone                 varchar(20),
    alternate_phone       varchar(20),
    email                 varchar(150),
    website               varchar(200),
    gstin                 varchar(15),
    pan                   varchar(10),
    state_code            varchar(2),
    bank_account_name     varchar(150),
    bank_name             varchar(150),
    bank_account_number   varchar(30),
    bank_ifsc             varchar(11),
    upi_id                varchar(100),
    other_payment_details varchar(1000),
    quotation_footer_note varchar(1000),
    quotation_terms       varchar(4000),
    updated_by            integer       REFERENCES users (user_id),
    created_at            timestamptz   NOT NULL DEFAULT now(),
    updated_at            timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_company_profile_tenant UNIQUE (tenant_id),
    CONSTRAINT ck_company_profile_pincode CHECK (pincode IS NULL OR pincode ~ '^[0-9]{6}$'),
    CONSTRAINT ck_company_profile_gstin CHECK (gstin IS NULL OR gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
    CONSTRAINT ck_company_profile_pan CHECK (pan IS NULL OR pan ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'),
    CONSTRAINT ck_company_profile_state_code CHECK (state_code IS NULL OR state_code ~ '^[0-9]{2}$'),
    CONSTRAINT ck_company_profile_state_matches_gstin CHECK (gstin IS NULL OR state_code IS NULL OR left(gstin, 2) = state_code),
    CONSTRAINT ck_company_profile_account CHECK (bank_account_number IS NULL OR bank_account_number ~ '^[0-9]{6,30}$'),
    CONSTRAINT ck_company_profile_ifsc CHECK (bank_ifsc IS NULL OR bank_ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
    CONSTRAINT ck_company_profile_upi CHECK (upi_id IS NULL OR upi_id ~ '^[A-Za-z0-9._-]{2,64}@[A-Za-z]{2,64}$'),
    CONSTRAINT ck_company_profile_website CHECK (website IS NULL OR website ~ '^https://[^[:space:]]+$'),
    CONSTRAINT ck_company_profile_logo CHECK ((logo_file_name IS NULL) = (logo_content_type IS NULL)),
    CONSTRAINT ck_company_profile_logo_type CHECK (logo_content_type IS NULL OR logo_content_type IN ('image/png', 'image/jpeg'))
);

CREATE INDEX IF NOT EXISTS ix_company_profile_updated_by ON company_profile (updated_by);

-- Copy the old letterhead settings once. A value that does not fit its new column stops the script with a message
-- naming it, rather than being cut short (the owner shortens the setting and re-runs).
DO $$
DECLARE
    v_tenant   integer;
    v_old      record;
    c_keys     CONSTANT text[] := ARRAY['company_name', 'company_address', 'company_phone', 'company_bank_details', 'quotation_footer_note'];
    c_limits   CONSTANT integer[] := ARRAY[150, 200, 20, 1000, 1000];
    v_i        integer;
    v_value    text;
BEGIN
    FOR v_tenant IN SELECT DISTINCT s.tenant_id FROM app_settings s WHERE s.setting_key = ANY (c_keys) LOOP
        FOR v_i IN 1 .. array_length(c_keys, 1) LOOP
            SELECT btrim(s.setting_value) INTO v_value FROM app_settings s WHERE s.tenant_id = v_tenant AND s.setting_key = c_keys[v_i];
            IF length(v_value) > c_limits[v_i] THEN
                RAISE EXCEPTION 'Setting % of tenant % is % characters long; the company profile allows % for it. Shorten it with an UPDATE of app_settings and run this script again.',
                    c_keys[v_i], v_tenant, length(v_value), c_limits[v_i];
            END IF;
        END LOOP;
        SELECT NULLIF(btrim(max(CASE WHEN s.setting_key = 'company_name' THEN s.setting_value END)), '') AS name,
               NULLIF(btrim(max(CASE WHEN s.setting_key = 'company_address' THEN s.setting_value END)), '') AS address,
               NULLIF(btrim(max(CASE WHEN s.setting_key = 'company_phone' THEN s.setting_value END)), '') AS phone,
               NULLIF(btrim(max(CASE WHEN s.setting_key = 'company_bank_details' THEN s.setting_value END)), '') AS bank,
               NULLIF(btrim(max(CASE WHEN s.setting_key = 'quotation_footer_note' THEN s.setting_value END)), '') AS footer
          INTO v_old FROM app_settings s WHERE s.tenant_id = v_tenant;
        -- The old name goes into both names; the old address into line 1; the free-text bank details into "other payment details".
        INSERT INTO company_profile (tenant_id, legal_name, display_name, address_line1, phone, other_payment_details, quotation_footer_note)
        VALUES (v_tenant, v_old.name, v_old.name, v_old.address, v_old.phone, v_old.bank, v_old.footer)
        ON CONFLICT (tenant_id) DO NOTHING;
    END LOOP;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('20_company_profile_schema.sql')
ON CONFLICT DO NOTHING;
