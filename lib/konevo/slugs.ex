defmodule Konevo.Slugs do
  @moduledoc """
  Helpers for generating org-scoped record slugs.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias Konevo.Repo

  @fallback "record"

  def maybe_put_slug(changeset, schema, org_id, fields, opts \\ []) do
    exclude_id = Keyword.get(opts, :exclude_id)

    if changeset.valid? && should_refresh_slug?(changeset, fields) do
      base =
        changeset
        |> source_text(fields)
        |> base_slug()

      changeset
      |> put_change(:slug, unique_slug(schema, org_id, base, exclude_id))
    else
      changeset
    end
  end

  def unique_slug(schema, org_id, base, exclude_id \\ nil) do
    schema
    |> slug_prefix_query(org_id, base, exclude_id)
    |> Repo.all()
    |> find_next_slug(base)
  end

  def base_slug(value) do
    value
    |> to_string()
    |> Slugy.slugify()
    |> case do
      "" -> @fallback
      slug -> slug
    end
  end

  defp should_refresh_slug?(changeset, fields) do
    blank?(get_field(changeset, :slug)) || Enum.any?(fields, &changed?(changeset, &1))
  end

  defp source_text(changeset, fields) do
    fields
    |> Enum.map(&get_field(changeset, &1))
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp slug_prefix_query(schema, org_id, base, exclude_id) do
    pattern = "#{base}-%"

    schema
    |> where([r], r.organization_id == ^org_id)
    |> where([r], r.slug == ^base or like(r.slug, ^pattern))
    |> maybe_exclude(exclude_id)
    |> select([r], r.slug)
  end

  defp maybe_exclude(query, nil), do: query
  defp maybe_exclude(query, id), do: where(query, [r], r.id != ^id)

  defp find_next_slug(existing_slugs, base) do
    if base in existing_slugs do
      suffix =
        existing_slugs
        |> Enum.map(&slug_suffix(&1, base))
        |> Enum.max(fn -> 0 end)

      "#{base}-#{suffix + 1}"
    else
      base
    end
  end

  defp slug_suffix(slug, base) do
    case Regex.run(~r/^#{Regex.escape(base)}-(\d+)$/, slug) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end

  defp blank?(value), do: value in [nil, ""]
end
