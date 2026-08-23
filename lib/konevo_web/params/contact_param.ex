defimpl Phoenix.Param, for: Konevo.Contacts.Contact do
  def to_param(%{slug: slug}) when is_binary(slug) and slug != "", do: slug
  def to_param(%{id: id}), do: to_string(id)
end
