defmodule Konevo.Repo.Migrations.CreateAiAssistantData do
  use Ecto.Migration

  def change do
    create table(:ai_conversations) do
      add :title, :string
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:ai_conversations, [:organization_id, :user_id, :updated_at])

    create table(:ai_messages) do
      add :role, :string, null: false
      add :content, :text, null: false
      add :metadata, :map, null: false, default: %{}
      add :model_used, :string
      add :conversation_id, references(:ai_conversations, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:ai_messages, [:conversation_id, :inserted_at])
    create index(:ai_messages, [:organization_id])

    create table(:ai_runs) do
      add :kind, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :provider, :string
      add :model_used, :string
      add :input, :map, null: false, default: %{}
      add :output, :map, null: false, default: %{}
      add :error_message, :text
      add :input_tokens, :integer
      add :output_tokens, :integer
      add :conversation_id, references(:ai_conversations, on_delete: :nilify_all)
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:ai_runs, [:organization_id, :inserted_at])
    create index(:ai_runs, [:conversation_id, :inserted_at])

    create table(:ai_preferences) do
      add :tone, :string, null: false, default: "professional"
      add :language, :string, null: false, default: "English"
      add :response_length, :string, null: false, default: "concise"
      add :signature, :text
      add :custom_instruction, :text
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_preferences, [:organization_id, :user_id])

    create table(:company_intelligence_snapshots) do
      add :source, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :retrieved_at, :utc_datetime, null: false
      add :company_id, references(:companies, on_delete: :delete_all)
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :requested_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:company_intelligence_snapshots, [:organization_id, :company_id, :inserted_at])
    create index(:company_intelligence_snapshots, [:source])
  end
end
