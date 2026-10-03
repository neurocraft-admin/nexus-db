-- Foundation: logins, the single role x resource permission model, menu, settings, document numbers.

CREATE TABLE IF NOT EXISTS roles (
    role_id     integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id   integer      NOT NULL,
    role_name   varchar(100) NOT NULL,
    is_active   boolean      NOT NULL DEFAULT true,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_roles_tenant_role_name UNIQUE (tenant_id, role_name)
);

CREATE TABLE IF NOT EXISTS users (
    user_id               integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id             integer      NOT NULL,
    user_name             varchar(100) NOT NULL,
    full_name             varchar(150) NOT NULL,
    mobile                varchar(15),
    password_hash         varchar(500) NOT NULL,
    role_id               integer      NOT NULL REFERENCES roles (role_id),
    user_type             varchar(10)  NOT NULL CHECK (user_type IN ('admin', 'staff')),
    must_change_password  boolean      NOT NULL DEFAULT true,
    failed_attempts       integer      NOT NULL DEFAULT 0,
    locked_until          timestamptz,
    last_login_at         timestamptz,
    is_active             boolean      NOT NULL DEFAULT true,
    created_at            timestamptz  NOT NULL DEFAULT now(),
    updated_at            timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_users_tenant_user_name UNIQUE (tenant_id, user_name)
);
CREATE INDEX IF NOT EXISTS ix_users_role_id ON users (role_id);

CREATE TABLE IF NOT EXISTS resources (
    resource_id    integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id      integer      NOT NULL,
    resource_code  varchar(50)  NOT NULL,
    display_name   varchar(100) NOT NULL,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    updated_at     timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_resources_tenant_code UNIQUE (tenant_id, resource_code)
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id      integer     NOT NULL REFERENCES roles (role_id),
    resource_id  integer     NOT NULL REFERENCES resources (resource_id),
    tenant_id    integer     NOT NULL,
    can_view     boolean     NOT NULL DEFAULT false,
    can_create   boolean     NOT NULL DEFAULT false,
    can_update   boolean     NOT NULL DEFAULT false,
    can_delete   boolean     NOT NULL DEFAULT false,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, resource_id)
);
CREATE INDEX IF NOT EXISTS ix_role_permissions_resource_id ON role_permissions (resource_id);

CREATE TABLE IF NOT EXISTS menu_items (
    menu_item_id  integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id     integer      NOT NULL,
    parent_id     integer      REFERENCES menu_items (menu_item_id),
    title         varchar(100) NOT NULL,
    icon          varchar(50),
    url           varchar(200),
    sort_order    integer      NOT NULL DEFAULT 0,
    resource_id   integer      REFERENCES resources (resource_id),
    is_active     boolean      NOT NULL DEFAULT true,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_menu_items_parent_id   ON menu_items (parent_id);
CREATE INDEX IF NOT EXISTS ix_menu_items_resource_id ON menu_items (resource_id);
-- coalesce makes top-level titles unique too, which keeps seed scripts re-runnable.
CREATE UNIQUE INDEX IF NOT EXISTS uq_menu_items_tenant_parent_title
    ON menu_items (tenant_id, COALESCE(parent_id, 0), title);

CREATE TABLE IF NOT EXISTS menu_access (
    role_id       integer     NOT NULL REFERENCES roles (role_id),
    menu_item_id  integer     NOT NULL REFERENCES menu_items (menu_item_id),
    tenant_id     integer     NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, menu_item_id)
);
CREATE INDEX IF NOT EXISTS ix_menu_access_menu_item_id ON menu_access (menu_item_id);

CREATE TABLE IF NOT EXISTS app_settings (
    setting_id     integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id      integer      NOT NULL,
    setting_key    varchar(100) NOT NULL,
    setting_value  varchar(500) NOT NULL,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    updated_at     timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_app_settings_tenant_key UNIQUE (tenant_id, setting_key)
);

CREATE TABLE IF NOT EXISTS document_counters (
    tenant_id   integer     NOT NULL,
    doc_type    varchar(10) NOT NULL,
    doc_year    integer     NOT NULL,
    last_no     integer     NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, doc_type, doc_year)
);

INSERT INTO deployment_log (script_name) VALUES ('01_foundation_schema.sql')
ON CONFLICT DO NOTHING;
