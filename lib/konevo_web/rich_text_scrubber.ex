defmodule KonevoWeb.RichTextScrubber do
  @moduledoc false

  use HtmlSanitizeEx, extend: :basic_html

  allow_tag_with_these_attributes("h1", ["style"])
  allow_tag_with_these_attributes("h2", ["style"])
  allow_tag_with_these_attributes("h3", ["style"])
  allow_tag_with_these_attributes("h4", ["style"])
  allow_tag_with_these_attributes("img", ["alt", "height", "src", "style", "title", "width"])
  allow_tag_with_these_attributes("mark", ["style"])
  allow_tag_with_these_attributes("p", ["style"])
  allow_tag_with_these_attributes("span", ["style"])
end
