-- Checks everything fn_create_ticket is given, before anything is written. Messages name the field (COLUMN) so the API
-- can show them under it.
--   22023 invalid parameter - no description or over 500 characters (description); neither or both of the issue type
--                             and the free text, or free text over 100 characters (issueTypeId, otherIssueText);
--                             a source that is not portal or internal (source); an internal ticket without its creator
--                             or a portal ticket with one (createdBy); an attachment that is only partly given
--   P0002 not found         - unknown issue type (issueTypeId)
--   NX409 rule conflict     - an issue type that is switched off (issueTypeId)
CREATE OR REPLACE PROCEDURE sp_check_ticket_fields(
    p_tenant_id integer, p_issue_type_id integer, p_other_issue_text varchar, p_description varchar,
    p_source varchar, p_created_by integer, p_attachment_name varchar, p_attachment_stored varchar,
    p_attachment_type varchar, p_attachment_size integer)
LANGUAGE plpgsql AS $$
DECLARE
    c_description_max CONSTANT integer := 500;
    c_other_text_max  CONSTANT integer := 100;
    v_other  varchar := NULLIF(btrim(p_other_issue_text), '');
    v_active boolean;
BEGIN
    IF p_description IS NULL OR btrim(p_description) = '' OR length(btrim(p_description)) > c_description_max THEN
        RAISE EXCEPTION 'Describe the problem in up to % characters', c_description_max USING ERRCODE = '22023', COLUMN = 'description';
    END IF;
    IF (p_issue_type_id IS NULL) = (v_other IS NULL) THEN
        RAISE EXCEPTION 'Choose an issue type, or describe the issue in the Other box (not both)' USING ERRCODE = '22023', COLUMN = 'issueTypeId';
    END IF;
    IF length(v_other) > c_other_text_max THEN
        RAISE EXCEPTION 'The issue can be up to % characters', c_other_text_max USING ERRCODE = '22023', COLUMN = 'otherIssueText';
    END IF;
    IF p_source IS NULL OR p_source NOT IN ('portal', 'internal') THEN
        RAISE EXCEPTION 'A ticket comes from the portal or from staff' USING ERRCODE = '22023', COLUMN = 'source';
    END IF;
    IF (p_source = 'portal') <> (p_created_by IS NULL) THEN
        RAISE EXCEPTION 'A staff ticket needs the person who raised it, and a portal ticket has none' USING ERRCODE = '22023', COLUMN = 'createdBy';
    END IF;
    IF num_nonnulls(p_attachment_name, p_attachment_stored, p_attachment_type, p_attachment_size) NOT IN (0, 4) THEN
        RAISE EXCEPTION 'An attachment needs its name, stored name, type and size' USING ERRCODE = '22023', COLUMN = 'attachment';
    END IF;
    IF p_issue_type_id IS NOT NULL THEN
        SELECT t.is_active INTO v_active FROM issue_types t WHERE t.issue_type_id = p_issue_type_id AND t.tenant_id = p_tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Issue type % not found', p_issue_type_id USING ERRCODE = 'P0002', COLUMN = 'issueTypeId';
        END IF;
        IF NOT v_active THEN
            RAISE EXCEPTION 'That issue type is no longer in use' USING ERRCODE = 'NX409', COLUMN = 'issueTypeId';
        END IF;
    END IF;
END;
$$;
