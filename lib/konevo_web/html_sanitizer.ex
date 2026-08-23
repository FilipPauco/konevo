defmodule KonevoWeb.HTMLSanitizer do
  @moduledoc """
  Sanitizes user-authored HTML before rendering it in HEEx.
  """

  def basic_html(nil), do: {:safe, ""}
  def basic_html(""), do: {:safe, ""}

  def basic_html(html) when is_binary(html) do
    {:safe, sanitize_or_format_plain_text(html)}
  end

  def email_html(nil), do: {:safe, ""}
  def email_html(""), do: {:safe, ""}

  def email_html(html) when is_binary(html) do
    {:safe, email_html_string(html)}
  end

  def email_html_string(nil), do: ""
  def email_html_string(""), do: ""

  def email_html_string(html) when is_binary(html) do
    html
    |> normalize_email_html()
    |> email_body_fragment()
    |> strip_email_non_body_blocks()
    |> sanitize_or_format_email()
  end

  def email_html_like?(nil), do: false

  def email_html_like?(html) when is_binary(html) do
    html_like?(html) or escaped_html_like?(html)
  end

  defp sanitize_or_format_plain_text(html) do
    if String.match?(html, ~r/<[a-z][\s\S]*>/i) do
      KonevoWeb.RichTextScrubber.sanitize(html)
    else
      plain_text_to_html(html)
    end
  end

  defp sanitize_or_format_email(html) do
    html =
      if html_like?(html) do
        KonevoWeb.EmailHTMLScrubber.sanitize(html)
      else
        html
        |> strip_leading_css_dump()
        |> plain_text_to_html()
      end

    html
  end

  defp normalize_email_html(html) do
    html = String.trim(html)

    if escaped_html_like?(html) and not html_like?(html) do
      decode_common_html_entities(html)
    else
      html
    end
  end

  defp html_like?(html) do
    String.match?(html, ~r/<(?:!doctype|html|body|table|div|p|span|br|a|img|blockquote)\b/i)
  end

  defp escaped_html_like?(html) do
    String.match?(html, ~r/&lt;(?:!doctype|html|body|table|div|p|span|br|a|img|blockquote)\b/i)
  end

  defp decode_common_html_entities(html) do
    html
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
  end

  defp email_body_fragment(html) do
    case Regex.run(~r/<body\b[^>]*>([\s\S]*?)<\/body>/i, html, capture: :all_but_first) do
      [body] -> body
      _ -> html
    end
  end

  defp strip_email_non_body_blocks(html) do
    html
    |> String.replace(~r/<!doctype[\s\S]*?>/i, "")
    |> String.replace(~r/<head\b[^>]*>[\s\S]*?<\/head>/i, "")
    |> String.replace(~r/<style\b[^>]*>[\s\S]*?<\/style>/i, "")
    |> String.replace(~r/<script\b[^>]*>[\s\S]*?<\/script>/i, "")
    |> String.replace(~r/<noscript\b[^>]*>[\s\S]*?<\/noscript>/i, "")
    |> String.replace(~r/<meta\b[^>]*>/i, "")
    |> String.replace(~r/<link\b[^>]*>/i, "")
    |> String.replace(~r/<title\b[^>]*>[\s\S]*?<\/title>/i, "")
  end

  defp strip_leading_css_dump(text) do
    trimmed = String.trim_leading(text)
    sample = String.slice(trimmed, 0, 2_000)

    if css_dump?(sample) do
      case Regex.run(~r/\A[\s\S]*\}\s+([A-Z0-9][\s\S]*)\z/u, trimmed, capture: :all_but_first) do
        [content] -> content
        _ -> text
      end
    else
      text
    end
  end

  defp css_dump?(sample) do
    String.contains?(sample, [
      "@font-face",
      "@media",
      "color-scheme",
      "-webkit-text-size-adjust",
      "mso-table-rspace"
    ])
  end

  defp plain_text_to_html(text) do
    text
    |> String.split(~r/\R{2,}/, trim: true)
    |> Enum.map_join("", &plain_paragraph/1)
  end

  defp plain_paragraph(text) do
    text =
      text
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> String.replace(~r/\R/, "<br>")

    "<p>#{text}</p>"
  end
end
