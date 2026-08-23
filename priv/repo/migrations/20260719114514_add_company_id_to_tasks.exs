defmodule Konevo.Repo.Migrations.AddCompanyIdToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :company_id, references(:companies, on_delete: :nilify_all)
    end

    execute(
      """
      UPDATE tasks AS t
      SET company_id = COALESCE(
        (SELECT c.company_id FROM contacts AS c WHERE c.id = t.contact_id),
        (
          SELECT c.company_id
          FROM deals AS d
          JOIN contacts AS c ON c.id = d.contact_id
          WHERE d.id = t.deal_id
        )
      )
      WHERE t.company_id IS NULL
        AND (t.contact_id IS NOT NULL OR t.deal_id IS NOT NULL)
      """,
      "SELECT 1"
    )

    create index(:tasks, [:company_id])
  end
end
