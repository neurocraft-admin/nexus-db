-- One transaction: purchase header (number from fn_next_document_no, prefix PUR), its lines, one 'in' movement
-- and a stock increase per line, and optionally the item's cost price set to the line's unit cost (latest
-- cost, no average costing). Anything that fails rolls back all of it, including the document number.
-- p_lines is a JSON array of {"itemId": 1, "quantity": 2.5, "unitCost": 10.00}.
-- Returns the new purchase id in p_purchase_id. Errors are those of fn_check_purchase_header,
-- sp_check_purchase_lines and sp_stock_in (22023, P0002, NX409, 22003 for a number too large).
CREATE OR REPLACE PROCEDURE sp_record_purchase(
    p_tenant_id integer, p_supplier_id bigint, p_purchase_date date, p_reference_text varchar,
    p_update_cost_price boolean, p_lines jsonb, p_created_by integer, OUT p_purchase_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    c_doc_type CONSTANT varchar := 'PUR';
    v_no       varchar;
BEGIN
    PERFORM fn_check_purchase_header(p_tenant_id, p_supplier_id, p_purchase_date);
    CALL sp_check_purchase_lines(p_tenant_id, p_lines);

    v_no := fn_next_document_no(p_tenant_id, c_doc_type);
    INSERT INTO purchases (tenant_id, purchase_no, supplier_id, purchase_date, reference_text, created_by)
    VALUES (p_tenant_id, v_no, p_supplier_id, p_purchase_date, NULLIF(btrim(p_reference_text), ''), p_created_by)
    RETURNING purchases.purchase_id INTO p_purchase_id;

    CALL sp_add_purchase_lines(p_tenant_id, p_purchase_id, v_no, p_update_cost_price, p_lines, p_created_by);
END;
$$;
