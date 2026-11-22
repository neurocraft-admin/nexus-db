-- The text of a quotation (payment terms, terms and conditions) is rich text stored as a restricted HTML: only the bare tags p, br, strong, em,
-- h1, h2, h3, ul, ol and li, with NO attributes, and every other < or > written as &lt; or &gt;. The API sanitises on save; this is the same rule
-- as a last guard in the database, so nothing else can ever be stored (a script tag, a link, a style or an event attribute is refused).
-- NULL is allowed (no text). Returns true when the text follows the rule.
CREATE OR REPLACE FUNCTION fn_html_is_allowed(p_html text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    SELECT p_html IS NULL OR (
        NOT EXISTS (SELECT 1 FROM regexp_matches(p_html, '<[^<>]*>', 'g') AS m
                     WHERE m[1] !~* '^</?(p|br|strong|em|h[1-3]|ul|ol|li)\s*/?>$')
        AND regexp_replace(p_html, '<[^<>]*>', '', 'g') !~ '[<>]');
$$;
