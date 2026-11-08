-- Module 1 (Leads): gives Sales > Leads its own menu icon ('funnel') instead of sharing 'people' with Users.
-- Script 18 has been applied on the owner's database and is never edited, so this is a new script. Re-runnable.
UPDATE menu_items
   SET icon = 'funnel'
 WHERE url = '/sales/leads' AND icon <> 'funnel';

INSERT INTO deployment_log (script_name) VALUES ('19_leads_menu_icon.sql')
ON CONFLICT DO NOTHING;
