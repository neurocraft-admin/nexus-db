-- Can this staff user see this quotation? A quotation made for a lead is visible only to someone who may see that lead
-- (p_visible_to is the staff user's id; NULL, an admin, sees everything). A quotation with no lead is visible to all.
-- A quotation that does not exist is reported visible, so the caller's own "not found" answer is the one given.
CREATE OR REPLACE FUNCTION fn_quotation_visible_to(p_tenant_id integer, p_quotation_id bigint, p_visible_to integer)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_visible_to IS NULL OR NOT EXISTS (
        SELECT 1 FROM quotations q JOIN leads l ON l.lead_id = q.lead_id
         WHERE q.quotation_id = p_quotation_id AND q.tenant_id = p_tenant_id AND l.assigned_to IS DISTINCT FROM p_visible_to);
$$;
