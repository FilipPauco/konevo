defmodule Konevo.Repo.Migrations.AddTaskInstructionsToAiPreferences do
  use Ecto.Migration

  def up do
    alter table(:ai_preferences) do
      add :task_instructions, :text
    end

    execute("""
    UPDATE ai_preferences AS preference
    SET task_instructions = source.instructions
    FROM (
      SELECT DISTINCT ON (sequence.organization_id, sequence.created_by_id)
        sequence.organization_id,
        sequence.created_by_id,
        rule.action_config ->> 'instructions' AS instructions
      FROM automation_sequences AS sequence
      INNER JOIN automation_rules AS rule ON rule.sequence_id = sequence.id
      WHERE sequence.trigger_config ->> 'workflow_type' = 'inbound_email_task'
        AND rule.action_type = 'prepare_task'
        AND NULLIF(BTRIM(rule.action_config ->> 'instructions'), '') IS NOT NULL
      ORDER BY sequence.organization_id, sequence.created_by_id, sequence.updated_at DESC, sequence.id DESC
    ) AS source
    WHERE preference.organization_id = source.organization_id
      AND preference.user_id = source.created_by_id
      AND preference.task_instructions IS NULL
    """)
  end

  def down do
    alter table(:ai_preferences) do
      remove :task_instructions
    end
  end
end
