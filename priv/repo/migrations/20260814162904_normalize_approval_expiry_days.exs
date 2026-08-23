defmodule Konevo.Repo.Migrations.NormalizeApprovalExpiryDays do
  use Ecto.Migration

  def up do
    execute("UPDATE organizations SET approval_expiry_days = 1 WHERE approval_expiry_days < 1")

    execute("""
    UPDATE automation_sequences
    SET trigger_config = jsonb_set(trigger_config, '{idle_days}', '1'::jsonb)
    WHERE trigger_config->>'workflow_type' = 'no_reply_follow_up'
      AND COALESCE(trigger_config->>'idle_days', '0') IN ('', '0')
    """)

    execute("""
    UPDATE automation_rules AS rule
    SET delay_seconds = 86400
    FROM automation_sequences AS sequence
    WHERE rule.sequence_id = sequence.id
      AND rule.action_type = 'wait'
      AND sequence.trigger_config->>'workflow_type' = 'no_reply_follow_up'
      AND rule.delay_seconds < 86400
    """)
  end

  def down, do: :ok
end
