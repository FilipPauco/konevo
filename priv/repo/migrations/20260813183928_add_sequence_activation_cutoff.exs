defmodule Konevo.Repo.Migrations.AddSequenceActivationCutoff do
  use Ecto.Migration

  def up do
    alter table(:automation_sequences) do
      add :activated_at, :utc_datetime
    end

    execute("""
    UPDATE automation_sequences
    SET activated_at = NOW()
    WHERE status = 'active'
      AND activated_at IS NULL
    """)

    execute("""
    UPDATE message_drafts
    SET body = btrim(
      regexp_replace(
        regexp_replace(
          regexp_replace(body, '<br\\s*/?>', E'\\n', 'gi'),
          '</(p|div|li|h[1-6])\\s*>', E'\\n\\n', 'gi'
        ),
        '<[^>]+>', '', 'g'
      )
    )
    WHERE ai_generated = TRUE
      AND status = 'pending'
      AND body ~* '<[a-z][^>]*>'
    """)
  end

  def down do
    alter table(:automation_sequences) do
      remove :activated_at
    end
  end
end
