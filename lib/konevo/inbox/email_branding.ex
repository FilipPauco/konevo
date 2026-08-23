defmodule Konevo.Inbox.EmailBranding do
  @moduledoc """
  Applies sender-specific signatures to outbound email bodies.
  """

  alias Konevo.Inbox.EmailIntegration

  def sanitize_attrs(attrs) when is_map(attrs) do
    attrs
    |> sanitize_html_field(:signature_html)
    |> sanitize_html_field("signature_html")
  end

  def apply(body, %EmailIntegration{} = integration) do
    body = to_string(body)

    cond do
      blank?(signature(integration)) ->
        body

      html_body?(body) or not blank?(integration.signature_html) ->
        render_html(body, integration)

      true ->
        render_text(body, integration)
    end
  end

  def apply(body, _integration), do: body

  defp render_html(body, integration) do
    [
      html_content(body),
      section(signature(integration), "konevo-email-signature")
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n")
  end

  defp render_text(body, integration) do
    [
      String.trim(body),
      text_content(integration.signature_html)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp html_content(body) do
    if html_body?(body), do: body, else: text_to_html(body)
  end

  defp section(nil, _class), do: nil
  defp section("", _class), do: nil

  defp section(html, class) do
    ~s(<div class="#{class}">#{html}</div>)
  end

  defp signature(%EmailIntegration{signature_html: html}) when html not in [nil, ""], do: html

  defp signature(_integration), do: nil

  defp sanitize_html_field(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(attrs, key, sanitize_html(value))
      :error -> attrs
    end
  end

  defp sanitize_html(nil), do: nil

  defp sanitize_html(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      html -> html |> html_fragment() |> KonevoWeb.RichTextScrubber.sanitize()
    end
  end

  defp html_fragment(value) do
    if html_body?(value), do: value, else: text_to_html(value)
  end

  defp text_to_html(text) do
    text
    |> String.split(~r/\R{2,}/, trim: true)
    |> Enum.map_join("", &paragraph/1)
  end

  defp paragraph(text) do
    text =
      text
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> String.replace(~r/\R/, "<br>")

    "<p>#{text}</p>"
  end

  defp text_content(nil), do: nil

  defp text_content(value) do
    value
    |> to_string()
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<\/p>/i, "\n\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> decode_text_entities()
    |> String.trim()
  end

  defp decode_text_entities(text) do
    text
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
  end

  defp html_body?(body), do: is_binary(body) and String.match?(body, ~r/<[a-z][\s\S]*>/i)

  defp blank?(value), do: value in [nil, ""]
end
