-- Works out and saves the subsidy of a DRAFT quotation (capacity, category, amount, whether the amount was typed). Called by
-- sp_apply_quotation_document on every save, after the lines are written, so the invariant "subsidy never exceeds the customer payable" holds
-- however the quotation was edited.
--   customer payable = subtotal - extra charges - discount
-- The amount is: 0 when the category has no subsidy (none, commercial); the amount in the document when it has a number (an override, unless it
-- equals what the slabs suggest); the slab suggestion when it has a null subsidyAmount or no amount and the quotation was not overridden; the saved
-- amount when it was overridden before and the document says nothing. A suggestion never exceeds the payable; a typed amount that does is refused.
-- Keys that are not in p_document keep the quotation's saved capacity and category. p_prev_amount and p_prev_overridden are the subsidy the quotation
-- had BEFORE this save (NULL and false for a new one): sp_write_quotation may have lowered the stored amount to fit a smaller payable, so the
-- override that is kept, and refused when it no longer fits, is the earlier one.
--   22023 invalid parameter - a typed or kept subsidy above the customer payable (COLUMN subsidyAmount)
DROP PROCEDURE IF EXISTS sp_apply_subsidy(integer, bigint, jsonb);
CREATE OR REPLACE PROCEDURE sp_apply_subsidy(p_tenant_id integer, p_quotation_id bigint, p_document jsonb, p_prev_amount numeric, p_prev_overridden boolean)
LANGUAGE plpgsql AS $$
DECLARE
    v_doc      jsonb := COALESCE(p_document, '{}'::jsonb);
    v_q        record;
    v_category varchar;
    v_capacity numeric;
    v_suggest  numeric;
    v_amount   numeric;
    v_over     boolean;
BEGIN
    SELECT q.subtotal - q.extra_charges_amount - q.discount_amount AS payable, q.subsidy_category AS category, q.capacity_kw AS capacity,
           q.subsidy_amount AS amount INTO v_q
      FROM quotations q WHERE q.quotation_id = p_quotation_id AND q.tenant_id = p_tenant_id;
    v_category := CASE WHEN v_doc ? 'subsidyCategory' THEN COALESCE(v_doc ->> 'subsidyCategory', 'none') ELSE v_q.category END;
    v_capacity := CASE WHEN v_doc ? 'capacityKw' THEN (v_doc ->> 'capacityKw')::numeric ELSE v_q.capacity END;
    v_suggest := fn_suggest_subsidy(p_tenant_id, v_category, v_capacity);
    IF NOT EXISTS (SELECT 1 FROM subsidy_categories c WHERE c.tenant_id = p_tenant_id AND c.category_code = v_category AND c.has_subsidy) THEN
        v_amount := 0; v_over := false;
    ELSIF jsonb_typeof(v_doc -> 'subsidyAmount') = 'number' THEN
        v_amount := (v_doc ->> 'subsidyAmount')::numeric; v_over := v_amount IS DISTINCT FROM COALESCE(v_suggest, 0);
    ELSIF NOT (v_doc ? 'subsidyAmount') AND COALESCE(p_prev_overridden, false) THEN
        v_amount := p_prev_amount; v_over := true;
    ELSE
        v_amount := LEAST(COALESCE(v_suggest, 0), v_q.payable); v_over := false;
    END IF;
    IF v_amount > v_q.payable THEN
        RAISE EXCEPTION 'The subsidy (%) cannot be more than the customer payable (%)', v_amount, v_q.payable
            USING ERRCODE = '22023', COLUMN = 'subsidyAmount';
    END IF;
    UPDATE quotations SET subsidy_category = v_category, capacity_kw = v_capacity, subsidy_amount = v_amount, subsidy_overridden = v_over
     WHERE quotation_id = p_quotation_id AND tenant_id = p_tenant_id;
END;
$$;
