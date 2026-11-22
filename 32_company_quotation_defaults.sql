-- Company profile additions for the new quotation format. Re-runnable.
--   bank_branch               the branch of the bank account, printed in the bank block of the cost page (account name, number, IFSC, bank and
--                             UPI were already structured fields)
--   default_payment_terms_html, default_terms_html, default_cost_notes
--                             the company's starting text for a NEW template: payment terms and terms and conditions (restricted HTML: p, br,
--                             strong, em, h1 to h3, ul, ol, li, no attributes) and the footnotes of the cost page. A template copies them when it
--                             is created and a quotation copies its template; nothing reads these at print time except as the last fallback
--                             when a quotation and its template both have no terms.
-- The old plain-text quotation_terms becomes default_terms_html (one paragraph per line) the first time only. other_payment_details (the free
-- text that the structured bank fields replace) is NOT touched and NOT parsed: the PDF stops printing it, the Company screen shows it read-only
-- until the owner has moved what matters into the fields, and a held script (33) drops it only after the owner confirms the PDF from the
-- structured fields on nexus-pg. Script 24 (the old letterhead settings keys) stays held for the same reason.
ALTER TABLE company_profile
    ADD COLUMN IF NOT EXISTS bank_branch                varchar(150),
    ADD COLUMN IF NOT EXISTS default_payment_terms_html varchar(20000),
    ADD COLUMN IF NOT EXISTS default_terms_html         varchar(20000),
    ADD COLUMN IF NOT EXISTS default_cost_notes         varchar(1000);

UPDATE company_profile c
   SET default_terms_html = x.html
  FROM (SELECT p.company_profile_id,
               string_agg('<p>' || replace(replace(replace(btrim(l.line), '&', '&amp;'), '<', '&lt;'), '>', '&gt;') || '</p>', '' ORDER BY l.n) AS html
          FROM company_profile p
         CROSS JOIN LATERAL regexp_split_to_table(p.quotation_terms, E'\r?\n') WITH ORDINALITY AS l (line, n)
         WHERE p.default_terms_html IS NULL AND p.quotation_terms IS NOT NULL AND btrim(l.line) <> ''
         GROUP BY p.company_profile_id) x
 WHERE c.company_profile_id = x.company_profile_id AND c.default_terms_html IS NULL;

INSERT INTO deployment_log (script_name) VALUES ('32_company_quotation_defaults.sql')
ON CONFLICT DO NOTHING;
