defmodule Konevo.Repo.Migrations.ConsolidateEmailInstructions do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE ai_preferences
    SET email_instructions = CASE
      WHEN NULLIF(BTRIM(email_instructions), '') IS NULL THEN BTRIM(custom_instruction)
      ELSE BTRIM(email_instructions) || E'\\n\\n' || BTRIM(custom_instruction)
    END
    WHERE NULLIF(BTRIM(custom_instruction), '') IS NOT NULL
    """)

    alter table(:ai_preferences) do
      remove :custom_instruction
    end
  end

  def down do
    alter table(:ai_preferences) do
      add :custom_instruction, :text
    end
  end
end
