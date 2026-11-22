-- Adds (p_slab_id NULL) or changes a subsidy slab and returns its id in p_saved_id. A slab is a flat amount for a category and a capacity range
-- [from, to): the lower bound is included, the upper one is not, and no upper bound (NULL) means "and above". Two ACTIVE slabs of a category may
-- not overlap; the check runs under a lock on the category, so two simultaneous saves cannot both pass. A slab is switched off with p_is_active
-- false, never deleted. A quotation keeps the subsidy it was saved with, so this never changes an existing quotation.
--   22023 invalid parameter - see sp_check_subsidy_slab
--   P0002 not found         - an unknown slab or category
--   NX409 rule conflict     - the range overlaps another active slab of the category (COLUMN capacityFromKw)
CREATE OR REPLACE PROCEDURE sp_save_subsidy_slab(
    p_tenant_id integer, p_slab_id bigint, p_category_code varchar, p_from numeric, p_to numeric, p_amount numeric,
    p_is_active boolean, p_user_id integer, OUT p_saved_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_clash record;
BEGIN
    CALL sp_check_subsidy_slab(p_tenant_id, p_category_code, p_from, p_to, p_amount);
    PERFORM pg_advisory_xact_lock(hashtextextended('subsidy_slabs:' || p_tenant_id || ':' || p_category_code, 0));
    IF p_slab_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM subsidy_slabs s WHERE s.slab_id = p_slab_id AND s.tenant_id = p_tenant_id) THEN
        RAISE EXCEPTION 'Slab % not found', p_slab_id USING ERRCODE = 'P0002';
    END IF;
    IF COALESCE(p_is_active, true) THEN
        SELECT s.capacity_from_kw AS f, s.capacity_to_kw AS t INTO v_clash FROM subsidy_slabs s
         WHERE s.tenant_id = p_tenant_id AND s.category_code = p_category_code AND s.is_active
           AND s.slab_id IS DISTINCT FROM p_slab_id
           AND s.capacity_from_kw < COALESCE(p_to, 'Infinity'::numeric) AND p_from < COALESCE(s.capacity_to_kw, 'Infinity'::numeric)
         LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'This range overlaps the active slab from % kW%', v_clash.f, COALESCE(' up to ' || v_clash.t || ' kW', ' and above')
                USING ERRCODE = 'NX409', COLUMN = 'capacityFromKw';
        END IF;
    END IF;
    IF p_slab_id IS NULL THEN
        INSERT INTO subsidy_slabs (tenant_id, category_code, capacity_from_kw, capacity_to_kw, amount, is_active, updated_by)
        VALUES (p_tenant_id, p_category_code, p_from, p_to, p_amount, COALESCE(p_is_active, true), p_user_id)
        RETURNING subsidy_slabs.slab_id INTO p_saved_id;
    ELSE
        UPDATE subsidy_slabs
           SET category_code = p_category_code, capacity_from_kw = p_from, capacity_to_kw = p_to, amount = p_amount,
               is_active = COALESCE(p_is_active, true), updated_by = p_user_id, updated_at = now()
         WHERE subsidy_slabs.slab_id = p_slab_id AND subsidy_slabs.tenant_id = p_tenant_id
        RETURNING subsidy_slabs.slab_id INTO p_saved_id;
    END IF;
END;
$$;
