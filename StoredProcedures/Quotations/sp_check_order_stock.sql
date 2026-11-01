-- Before any stock leaves, checks the WHOLE order and names every problem at once, so the person sees the full list
-- instead of fixing one item at a time. Locks every item the order needs in item_id order (the same order
-- purchases and package saves use, so concurrent fulfilments cannot deadlock), then compares the total needed per
-- item with its stock. The message lists the items; fn_get_order_shortages returns the same list as rows.
--   NX409 rule conflict      - an inactive item or package component (checked first, because it is a data fix,
--                              not a stock shortage; the API turns it into a 409 listing the items)
--   NX411 insufficient stock - one or more items short; stock would go below zero
CREATE OR REPLACE PROCEDURE sp_check_order_stock(p_tenant_id integer, p_order_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_item record;
BEGIN
    FOR v_item IN
        SELECT i.item_id FROM items i
         WHERE i.tenant_id = p_tenant_id
           AND i.item_id IN (SELECT r.item_id FROM fn_get_order_requirements(p_tenant_id, p_order_id) r)
         ORDER BY i.item_id
           FOR UPDATE
    LOOP
        NULL;   -- taking the locks in id order is the whole job of this loop
    END LOOP;
    CALL sp_raise_order_stock_problem(p_tenant_id, p_order_id, true);
    CALL sp_raise_order_stock_problem(p_tenant_id, p_order_id, false);
END;
$$;
