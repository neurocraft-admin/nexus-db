-- Takes the stock an order needs out of the items, one sp_stock_out per item line and one per component of each
-- package line (quantity multiplied by the line's quantity), each tagged with the order number so the stock ledger
-- shows where it went. It does no transaction control and is only called by sp_fulfil_order after
-- sp_check_order_stock: if any stock-out still failed, the caller's transaction rolls every earlier one back.
CREATE OR REPLACE PROCEDURE sp_take_order_stock(
    p_tenant_id integer, p_order_id bigint, p_order_no varchar, p_created_by integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_req record;
BEGIN
    FOR v_req IN
        SELECT r.line_sort, r.item_id, r.quantity
          FROM fn_get_order_requirements(p_tenant_id, p_order_id) r
         ORDER BY r.line_sort, r.component_sort
    LOOP
        CALL sp_stock_out(p_tenant_id, v_req.item_id, v_req.quantity, 'order', p_order_id,
                          ('Order ' || p_order_no || ', line ' || v_req.line_sort)::varchar, p_created_by);
    END LOOP;
END;
$$;
