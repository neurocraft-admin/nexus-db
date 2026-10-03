CREATE OR REPLACE FUNCTION fn_get_setting(p_tenant_id integer, p_setting_key varchar)
RETURNS varchar
LANGUAGE sql STABLE AS $$
    SELECT s.setting_value
      FROM app_settings s
     WHERE s.tenant_id = p_tenant_id
       AND s.setting_key = p_setting_key;
$$;
