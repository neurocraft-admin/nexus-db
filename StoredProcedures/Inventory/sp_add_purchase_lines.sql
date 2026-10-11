-- Writes the lines of an already-created purchase header: a purchase_lines row, an 'in' movement and a stock
-- increase per line (through sp_stock_in), optionally the item's cost price set to the line's unit cost, and
-- finally the header's total. Lines are processed in item_id order, the same order sp_check_purchase_lines
-- locked them in. Called only by sp_record_purchase, inside its transaction.
CREATE OR REPLACE PROCEDURE sp_add_purchase_lines(
    p_tenant_id integer, p_purchase_id bigint, p_purchase_no varchar, p_update_cost_price boolean,
    p_lines jsonb, p_created_by integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_line  record;
    v_total numeric := 0;
BEGIN
    FOR v_line IN
        SELECT l."itemId" AS item_id, l.quantity, l."unitCost" AS unit_cost,
               round(l.quantity * l."unitCost", 2) AS line_total
          FROM jsonb_to_recordset(p_lines) AS l ("itemId" bigint, quantity numeric, "unitCost" numeric)
         ORDER BY l."itemId"
    LOOP
        INSERT INTO purchase_lines (tenant_id, purchase_id, item_id, quantity, unit_cost, line_total)
        VALUES (p_tenant_id, p_purchase_id, v_line.item_id, v_line.quantity, v_line.unit_cost, v_line.line_total);

        CALL sp_stock_in(p_tenant_id, v_line.item_id, v_line.quantity, v_line.unit_cost,
                         'purchase', p_purchase_id, p_purchase_no, p_created_by);

        IF COALESCE(p_update_cost_price, false) THEN
            UPDATE items SET cost_price = v_line.unit_cost, updated_at = now()
             WHERE item_id = v_line.item_id AND tenant_id = p_tenant_id;
        END IF;
        v_total := v_total + v_line.line_total;
    END LOOP;

    UPDATE purchases SET total_amount = v_total, updated_at = now()
     WHERE purchase_id = p_purchase_id AND tenant_id = p_tenant_id;
END;
$$;
