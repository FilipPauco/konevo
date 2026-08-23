defmodule Konevo.Repo.Migrations.AddSlugsToCompaniesContactsDeals do
  use Ecto.Migration

  def up do
    alter table(:companies) do
      add :slug, :citext
    end

    alter table(:contacts) do
      add :slug, :citext
    end

    alter table(:deals) do
      add :slug, :citext
    end

    backfill_slug(:companies, "name", "company")
    backfill_slug(:contacts, "concat_ws(' ', first_name, last_name)", "contact")
    backfill_slug(:deals, "title", "deal")

    alter table(:companies) do
      modify :slug, :citext, null: false
    end

    alter table(:contacts) do
      modify :slug, :citext, null: false
    end

    alter table(:deals) do
      modify :slug, :citext, null: false
    end

    create unique_index(:companies, [:organization_id, :slug])
    create unique_index(:contacts, [:organization_id, :slug])
    create unique_index(:deals, [:organization_id, :slug])
  end

  def down do
    drop index(:deals, [:organization_id, :slug])
    drop index(:contacts, [:organization_id, :slug])
    drop index(:companies, [:organization_id, :slug])

    alter table(:deals) do
      remove :slug
    end

    alter table(:contacts) do
      remove :slug
    end

    alter table(:companies) do
      remove :slug
    end
  end

  defp backfill_slug(table, source_sql, fallback) do
    execute("""
    WITH prepared AS (
      SELECT
        id,
        organization_id,
        COALESCE(
          NULLIF(
            trim(both '-' from regexp_replace(lower(COALESCE(NULLIF(#{source_sql}, ''), '#{fallback}')), '[^a-z0-9]+', '-', 'g')),
            ''
          ),
          '#{fallback}'
        ) AS base_slug,
        inserted_at
      FROM #{table}
    ),
    numbered AS (
      SELECT
        id,
        base_slug,
        row_number() OVER (PARTITION BY organization_id, base_slug ORDER BY inserted_at, id) AS position
      FROM prepared
    )
    UPDATE #{table}
    SET slug =
      numbered.base_slug ||
      CASE
        WHEN numbered.position = 1 THEN ''
        ELSE '-' || (numbered.position - 1)::text
      END
    FROM numbered
    WHERE #{table}.id = numbered.id
    """)
  end
end
