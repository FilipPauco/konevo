defmodule KonevoWeb.EmailHTMLScrubber do
  @moduledoc false

  use HtmlSanitizeEx, extend: :basic_html

  allow_tag_with_these_attributes("a", ["target", "rel", "title", "style"])
  allow_tag_with_these_attributes("blockquote", ["style"])
  allow_tag_with_these_attributes("center", ["style"])
  allow_tag_with_these_attributes("div", ["align", "class", "dir", "style"])
  allow_tag_with_these_attributes("font", ["color", "face", "size", "style"])
  allow_tag_with_these_attributes("h1", ["align", "style"])
  allow_tag_with_these_attributes("h2", ["align", "style"])
  allow_tag_with_these_attributes("h3", ["align", "style"])
  allow_tag_with_these_attributes("h4", ["align", "style"])
  allow_tag_with_these_attributes("h5", ["align", "style"])
  allow_tag_with_these_attributes("h6", ["align", "style"])
  allow_tag_with_these_attributes("hr", ["align", "size", "style", "width"])
  allow_tag_with_these_attributes("img", ["align", "border", "height", "src", "style", "width"])
  allow_tag_with_these_attributes("li", ["style"])
  allow_tag_with_these_attributes("ol", ["style"])
  allow_tag_with_these_attributes("p", ["align", "class", "dir", "style"])
  allow_tag_with_these_attributes("pre", ["style"])
  allow_tag_with_these_attributes("span", ["class", "dir", "style"])

  allow_tag_with_these_attributes("table", [
    "align",
    "bgcolor",
    "border",
    "cellpadding",
    "cellspacing",
    "class",
    "height",
    "role",
    "style",
    "width"
  ])

  allow_tag_with_these_attributes("tbody", ["align", "style", "valign"])

  allow_tag_with_these_attributes("td", [
    "align",
    "bgcolor",
    "class",
    "colspan",
    "height",
    "rowspan",
    "style",
    "valign",
    "width"
  ])

  allow_tag_with_these_attributes("tfoot", ["align", "style", "valign"])

  allow_tag_with_these_attributes("th", [
    "align",
    "bgcolor",
    "class",
    "colspan",
    "height",
    "rowspan",
    "style",
    "valign",
    "width"
  ])

  allow_tag_with_these_attributes("thead", ["align", "style", "valign"])
  allow_tag_with_these_attributes("tr", ["align", "bgcolor", "class", "style", "valign"])
  allow_tag_with_these_attributes("ul", ["style"])
end
