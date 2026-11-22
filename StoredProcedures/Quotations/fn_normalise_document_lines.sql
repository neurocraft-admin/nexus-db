-- The lines of a quotation or template as they are stored: description, unit and price filled in from the item or
-- package when the caller left them out, and each line total worked out as round(quantity x unit_price, 2), half
-- away from zero. Totals are always computed here, never taken from the client. An item line always takes the
-- item's unit and a package line is always counted in 'set'; a custom line keeps the unit it was given ('nos' if
-- empty). Call sp_check_document_lines and sp_check_document_references first.
-- make_text is the "make and warranty" text of the Make column: when the line has no "makeText" key an item line takes the item's default
-- (items.make_text); when the key is there (even null or blank) it is used as given, blank meaning none, so a person can clear it.
-- is_extra_charge marks a pass-through line (for example the KSEB charges), counted in the total but outside the customer payable.
DROP FUNCTION IF EXISTS fn_normalise_document_lines(integer, jsonb);
CREATE OR REPLACE FUNCTION fn_normalise_document_lines(p_tenant_id integer, p_lines jsonb)
RETURNS TABLE (sort_order integer, line_type varchar, item_id bigint, package_id bigint, description varchar,
               unit varchar, quantity numeric, unit_price numeric, line_total numeric, make_text varchar, is_extra_charge boolean)
LANGUAGE sql STABLE AS $$
    SELECT e.ord::integer, l."lineType"::varchar, l."itemId", l."packageId",
           COALESCE(NULLIF(btrim(l.description), ''), i.item_name, p.package_name)::varchar,
           (CASE l."lineType" WHEN 'item' THEN i.unit WHEN 'package' THEN 'set'
                              ELSE COALESCE(NULLIF(btrim(l.unit), ''), 'nos') END)::varchar,
           l.quantity,
           COALESCE(l."unitPrice", i.selling_price, p.package_price),
           round(l.quantity * COALESCE(l."unitPrice", i.selling_price, p.package_price), 2),
           (CASE WHEN e.line ? 'makeText' THEN NULLIF(btrim(e.line ->> 'makeText'), '') ELSE i.make_text END)::varchar,
           COALESCE(l."isExtraCharge", false)
      FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS e (line, ord)
     CROSS JOIN LATERAL jsonb_to_record(e.line) AS l ("lineType" text, "itemId" bigint, "packageId" bigint, description text, unit text,
                                                      quantity numeric, "unitPrice" numeric, "isExtraCharge" boolean)
      LEFT JOIN items i ON i.item_id = l."itemId" AND i.tenant_id = p_tenant_id
      LEFT JOIN packages p ON p.package_id = l."packageId" AND p.tenant_id = p_tenant_id
     ORDER BY e.ord;
$$;
