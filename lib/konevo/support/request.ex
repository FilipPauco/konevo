defmodule Konevo.Support.Request do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @topics ~w(question bug billing feature other)

  embedded_schema do
    field(:topic, :string, default: "question")
    field(:subject, :string)
    field(:message, :string)
  end

  def topics, do: @topics

  def changeset(request, attrs) do
    request
    |> cast(attrs, [:topic, :subject, :message])
    |> update_change(:subject, &normalize_subject/1)
    |> update_change(:message, &String.trim/1)
    |> validate_required([:topic, :subject, :message])
    |> validate_inclusion(:topic, @topics)
    |> validate_length(:subject, min: 3, max: 120)
    |> validate_length(:message, min: 10, max: 4_000)
  end

  defp normalize_subject(subject) do
    subject
    |> String.trim()
    |> String.replace(~r/[\r\n]+/, " ")
  end
end
