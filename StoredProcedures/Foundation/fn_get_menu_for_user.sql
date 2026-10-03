CREATE OR REPLACE FUNCTION fn_get_menu_for_user(p_tenant_id integer, p_user_id integer)
RETURNS TABLE (menu_item_id integer, parent_id integer, title varchar, icon varchar,
               url varchar, sort_order integer, resource_code varchar)
LANGUAGE sql STABLE AS $$
    SELECT m.menu_item_id, m.parent_id, m.title, m.icon, m.url, m.sort_order, x.resource_code
      FROM users u
      JOIN menu_access ma ON ma.role_id = u.role_id AND ma.tenant_id = u.tenant_id
      JOIN menu_items m   ON m.menu_item_id = ma.menu_item_id AND m.tenant_id = u.tenant_id
      LEFT JOIN resources x ON x.resource_id = m.resource_id
     WHERE u.tenant_id = p_tenant_id
       AND u.user_id = p_user_id
       AND u.is_active
       AND m.is_active
     ORDER BY m.sort_order, m.title;
$$;
