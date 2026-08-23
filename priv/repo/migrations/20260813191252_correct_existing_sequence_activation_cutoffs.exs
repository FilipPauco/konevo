defmodule Konevo.Repo.Migrations.CorrectExistingSequenceActivationCutoffs do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE automation_sequences
    SET activated_at = updated_at
    WHERE status = 'active'
      AND activated_at > updated_at
    """)
  end

  def down, do: :ok
end
