-- True when the role can see "My work" (the my_work resource with view). That is what makes a staff user assignable: a Clerk,
-- whose role has no my_work, cannot be given a task they could not see.
CREATE OR REPLACE FUNCTION fn_role_can_receive_work(p_tenant_id integer, p_role_id integer)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
          FROM role_permissions rp
          JOIN resources x ON x.resource_id = rp.resource_id
         WHERE rp.role_id = p_role_id AND rp.tenant_id = p_tenant_id AND x.tenant_id = p_tenant_id
           AND x.resource_code = 'my_work' AND rp.can_view);
$$;
