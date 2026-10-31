-- Module 3 (Quotations and orders): the settings the quotation PDF reads. Re-runnable; an existing value is never
-- overwritten, so editing a setting in the database survives a re-run.
--   company_name, company_address, company_phone  the letterhead (printed when filled)
--   company_bank_details                           free text, printed only when filled
--   quotation_footer_note                          free text at the foot of the PDF, printed only when filled
-- There is no GSTIN setting: NEXUS carries no GST anywhere (owner decision, 2026-10-17). Every value starts empty;
-- the owner fills them in before the first quotation is sent.
DO $$
DECLARE
    c_tenant_id CONSTANT integer := 1;   -- single-tenant for now; matches Tenant:DefaultId
BEGIN
    INSERT INTO app_settings (tenant_id, setting_key, setting_value)
    VALUES (c_tenant_id, 'company_name', ''),
           (c_tenant_id, 'company_address', ''),
           (c_tenant_id, 'company_phone', ''),
           (c_tenant_id, 'company_bank_details', ''),
           (c_tenant_id, 'quotation_footer_note', '')
    ON CONFLICT (tenant_id, setting_key) DO NOTHING;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('16_quotations_settings.sql')
ON CONFLICT DO NOTHING;
