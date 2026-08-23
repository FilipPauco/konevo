defmodule Konevo.Repo.Migrations.AddRlsPolicies do
  use Ecto.Migration

  def up do
    # Enable RLS on tenant-scoped tables.
    # The policy allows access when:
    #   - no tenant context is set (migrations, admin ops run as superuser)
    #   - the row's organization_id matches the current tenant setting
    #
    # NOTE: The table owner bypasses RLS by default in Postgres. To enforce RLS
    # even for the app db user (if it owns the tables), you would need to run:
    #   ALTER TABLE contacts FORCE ROW LEVEL SECURITY;
    # This requires your app's DB user to NOT be the superuser, and a separate
    # migration/admin role to bypass it. See docs for full setup.
    execute """
    ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
    """

    execute """
    CREATE POLICY tenant_isolation ON contacts
      USING (
        NULLIF(current_setting('app.current_tenant_id', true), '') IS NULL
        OR organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::bigint
      );
    """

    execute """
    ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
    """

    execute """
    CREATE POLICY tenant_isolation ON companies
      USING (
        NULLIF(current_setting('app.current_tenant_id', true), '') IS NULL
        OR organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::bigint
      );
    """

    execute """
    ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;
    """

    execute """
    CREATE POLICY tenant_isolation ON memberships
      USING (
        NULLIF(current_setting('app.current_tenant_id', true), '') IS NULL
        OR organization_id = NULLIF(current_setting('app.current_tenant_id', true), '')::bigint
      );
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS tenant_isolation ON contacts;"
    execute "ALTER TABLE contacts DISABLE ROW LEVEL SECURITY;"
    execute "DROP POLICY IF EXISTS tenant_isolation ON companies;"
    execute "ALTER TABLE companies DISABLE ROW LEVEL SECURITY;"
    execute "DROP POLICY IF EXISTS tenant_isolation ON memberships;"
    execute "ALTER TABLE memberships DISABLE ROW LEVEL SECURITY;"
  end
end
