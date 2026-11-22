-- Module 11 (Dashboard and reports): the read-only views, the indexes a report would otherwise scan for, and three settings.
-- Re-runnable. NO tables and NO writes to business data: every object here is a view, an index or a setting row.
-- The resources, permissions and menu are in 28_dashboard_menu.sql; the functions are in StoredProcedures/Reports/.
--
--   * The views are ROW-LEVEL (one row per lead, quotation, item, movement, ticket or order) and carry tenant_id and the
--     calendar dates in the business time zone (app_settings business_time_zone, default UTC). The brief's "by status and
--     month" shapes cannot answer a date range, a week grouping or "my own" numbers; the report functions group over these
--     rows. Callers always filter on tenant_id.
--   * All money is tax-inclusive as entered (owner decision 2026-10-17): there is no GST column anywhere.
--   * Settings (per tenant, an existing value is never overwritten):
--       ticket_overdue_days          an open ticket is overdue when it is older than this many days (default 7)
--       credit_terms_days            a customer's credit is overdue this many days after the oldest unpaid charge (default 30)
--       financial_year_start_month   month a financial year (and its quarters) starts: 4 = April (default)

-- The business time zone per tenant that has set one; a tenant without it means UTC (callers COALESCE).
CREATE OR REPLACE VIEW vw_business_time_zones AS
SELECT s.tenant_id, s.setting_value AS tz_name
  FROM app_settings s
 WHERE s.setting_key = 'business_time_zone' AND btrim(s.setting_value) <> '';

-- One row per ACTIVE lead: where it stands, who has it, and when it was created and closed (Won or Lost).
CREATE OR REPLACE VIEW vw_lead_pipeline AS
SELECT l.tenant_id, l.lead_id, l.lead_no, l.lead_name, l.mobile, l.lead_source_id, s.source_name, l.lead_status_id, st.status_name,
       st.sort_order AS status_sort_order, st.is_won, st.is_lost, l.is_closed, l.assigned_to, l.expected_value,
       l.next_follow_up_date, l.created_at,
       (l.created_at AT TIME ZONE COALESCE(z.tz_name, 'UTC'))::date AS created_date,
       l.closed_at,
       (l.closed_at AT TIME ZONE COALESCE(z.tz_name, 'UTC'))::date AS closed_date
  FROM leads l
  JOIN lead_sources s ON s.lead_source_id = l.lead_source_id
  JOIN lead_statuses st ON st.lead_status_id = l.lead_status_id
  LEFT JOIN vw_business_time_zones z ON z.tenant_id = l.tenant_id
 WHERE l.is_active;

-- One row per quotation: the party (customer or lead), who made it, whose lead it is on, and the moments that matter.
-- approved_at is the FIRST time it was approved (from the status log), so a quotation that was later converted to an order still
-- counts as approved. A quotation is "own" to a user when they created it or it is on a lead assigned to them.
CREATE OR REPLACE VIEW vw_quotation_summary AS
SELECT q.tenant_id, q.quotation_id, q.quotation_no, q.status, q.customer_id, q.lead_id,
       COALESCE(c.customer_name, ld.lead_name) AS party_name, COALESCE(c.mobile, ld.mobile) AS party_mobile,
       q.created_by, ld.assigned_to AS lead_assigned_to, q.total_amount, q.quotation_date, q.valid_until,
       q.created_at, (q.created_at AT TIME ZONE COALESCE(z.tz_name, 'UTC'))::date AS created_date,
       q.sent_at, (q.sent_at IS NOT NULL) AS was_sent,
       ap.approved_at, (ap.approved_at IS NOT NULL) AS was_approved, o.order_id
  FROM quotations q
  LEFT JOIN customers c ON c.customer_id = q.customer_id
  LEFT JOIN leads ld ON ld.lead_id = q.lead_id
  LEFT JOIN orders o ON o.quotation_id = q.quotation_id
  LEFT JOIN vw_business_time_zones z ON z.tenant_id = q.tenant_id
  LEFT JOIN LATERAL (SELECT min(g.changed_at) AS approved_at FROM quotation_status_log g
                      WHERE g.quotation_id = q.quotation_id AND g.to_status = 'approved') ap ON true;

-- One row per order, for revenue (a fulfilled order's total, by the day it was fulfilled).
CREATE OR REPLACE VIEW vw_order_report AS
SELECT o.tenant_id, o.order_id, o.order_no, o.customer_id, o.status, o.payment_mode, o.total_amount,
       o.created_at, (o.created_at AT TIME ZONE COALESCE(z.tz_name, 'UTC'))::date AS created_date,
       o.fulfilled_at, (o.fulfilled_at AT TIME ZONE COALESCE(z.tz_name, 'UTC'))::date AS fulfilled_date
  FROM orders o
  LEFT JOIN vw_business_time_zones z ON z.tenant_id = o.tenant_id;

-- One row per item with its stock position. is_low: an ACTIVE item with a reorder level whose stock is at or below it (the rule of
-- fn_get_low_stock_items). is_below_half: low AND stock is under half the reorder level.
CREATE OR REPLACE VIEW vw_inventory_status AS
SELECT i.tenant_id, i.item_id, i.item_code, i.item_name, i.unit, i.reorder_level, i.current_stock, i.is_active,
       (i.is_active AND i.reorder_level > 0 AND i.current_stock <= i.reorder_level) AS is_low,
       (i.is_active AND i.reorder_level > 0 AND i.current_stock * 2 < i.reorder_level) AS is_below_half,
       (i.current_stock - i.reorder_level) AS stock_over_minimum
  FROM items i;

-- One row per stock movement with its item and the business-time-zone day it happened.
CREATE OR REPLACE VIEW vw_stock_ledger AS
SELECT m.tenant_id, m.movement_id, m.item_id, i.item_code, i.item_name, i.unit, m.movement_type, m.quantity, m.signed_quantity,
       m.created_at, (m.created_at AT TIME ZONE COALESCE(z.tz_name, 'UTC'))::date AS created_date
  FROM stock_movements m
  JOIN items i ON i.item_id = m.item_id
  LEFT JOIN vw_business_time_zones z ON z.tenant_id = m.tenant_id;

-- One row per ticket. hours_to_resolve is set only when the ticket has been resolved (resolved_at; a reopened ticket has none until it
-- is resolved again, and a ticket closed without work never has one): the averages in the resolution report read only these.
CREATE OR REPLACE VIEW vw_ticket_summary AS
SELECT t.tenant_id, t.ticket_id, t.ticket_no, t.customer_id, c.customer_name, t.issue_type_id,
       COALESCE(it.issue_type_name, t.other_issue_text) AS issue_text, t.status, t.source, t.assigned_to,
       a.full_name AS assigned_to_name, t.created_by, t.created_at,
       (t.created_at AT TIME ZONE COALESCE(z.tz_name, 'UTC'))::date AS created_date,
       t.resolved_at,
       CASE WHEN t.resolved_at IS NOT NULL THEN extract(epoch FROM (t.resolved_at - t.created_at)) / 3600.0 END AS hours_to_resolve,
       (t.status IN ('open', 'in_progress')) AS is_open,
       (t.assigned_to IS NULL) AS is_unassigned
  FROM tickets t
  JOIN customers c ON c.customer_id = t.customer_id
  LEFT JOIN issue_types it ON it.issue_type_id = t.issue_type_id
  LEFT JOIN users a ON a.user_id = t.assigned_to
  LEFT JOIN vw_business_time_zones z ON z.tenant_id = t.tenant_id;

-- Indexes the date-range reads need (the movement ledger already has (tenant_id, created_at)).
CREATE INDEX IF NOT EXISTS ix_leads_tenant_created ON leads (tenant_id, created_at);
CREATE INDEX IF NOT EXISTS ix_leads_tenant_closed ON leads (tenant_id, closed_at) WHERE closed_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_tickets_tenant_created ON tickets (tenant_id, created_at);
CREATE INDEX IF NOT EXISTS ix_quotations_tenant_created ON quotations (tenant_id, created_at);
CREATE INDEX IF NOT EXISTS ix_orders_tenant_created ON orders (tenant_id, created_at);
CREATE INDEX IF NOT EXISTS ix_orders_tenant_fulfilled ON orders (tenant_id, fulfilled_at) WHERE fulfilled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_quotation_status_log_approved ON quotation_status_log (quotation_id) WHERE to_status = 'approved';
CREATE INDEX IF NOT EXISTS ix_customer_credit_ledgers_charges ON customer_credit_ledgers (customer_id, created_at) WHERE entry_type = 'charge';

DO $$
DECLARE
    c_tenant_id CONSTANT integer := 1;   -- single-tenant for now; matches Tenant:DefaultId
BEGIN
    INSERT INTO app_settings (tenant_id, setting_key, setting_value)
    VALUES (c_tenant_id, 'ticket_overdue_days', '7'),
           (c_tenant_id, 'credit_terms_days', '30'),
           (c_tenant_id, 'financial_year_start_month', '4')
    ON CONFLICT (tenant_id, setting_key) DO NOTHING;
END;
$$;

INSERT INTO deployment_log (script_name) VALUES ('27_dashboard_views.sql')
ON CONFLICT DO NOTHING;
