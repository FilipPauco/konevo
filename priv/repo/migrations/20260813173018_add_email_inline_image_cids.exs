defmodule Konevo.Repo.Migrations.AddEmailInlineImageCids do
  use Ecto.Migration

  def change do
    alter table(:emails) do
      add :inline_image_cids, :map, default: %{}, null: false
    end
  end
end
