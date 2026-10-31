-- Raises the error for one kind of stock problem on an order, if there is one; does nothing when there is none.
-- p_inactive = true looks for inactive items (NX409); false looks for items whose stock is below the total the order
-- needs (NX411). The message lists the items by code with what they have and what the order needs; the structured
-- list is fn_get_order_shortages. Called by sp_check_order_stock after it has locked the items, so the figures
-- cannot change underneath it.
CREATE OR REPLACE PROCEDURE sp_raise_order_stock_problem(p_tenant_id integer, p_order_id bigint, p_inactive boolean)
LANGUAGE plpgsql AS $$
DECLARE
    v_names text;
BEGIN
    SELECT string_agg(s.item_code || ' (has ' || trim_scale(s.available)::text
                      || ', needs ' || trim_scale(s.requested)::text || ')',
                      ', ' ORDER BY s.item_code)
      INTO v_names
      FROM fn_get_order_shortages(p_tenant_id, p_order_id) s
     WHERE s.problem = CASE WHEN p_inactive THEN 'inactive' ELSE 'short' END;
    IF v_names IS NULL THEN
        RETURN;
    END IF;
    IF p_inactive THEN
        RAISE EXCEPTION 'The order uses inactive items: %. Replace them first', v_names USING ERRCODE = 'NX409';
    END IF;
    RAISE EXCEPTION 'Not enough stock for: %', v_names USING ERRCODE = 'NX411';
END;
$$;
