defmodule KonevoWeb.HTMLSanitizerTest do
  use ExUnit.Case, async: true

  alias KonevoWeb.HTMLSanitizer

  test "keeps safe image sources in email HTML" do
    html = "<p>Hello</p><img src=\"https://images.example.com/logo.png\" width=\"240\">"

    assert HTMLSanitizer.email_html_string(html) =~ "src=\"https://images.example.com/logo.png\""
  end

  test "removes scripts and event handlers from email HTML" do
    html =
      "<img src=\"https://images.example.com/logo.png\" onerror=\"alert(1)\"><script>alert(1)</script>"

    sanitized = HTMLSanitizer.email_html_string(html)

    assert sanitized =~ "src=\"https://images.example.com/logo.png\""
    refute sanitized =~ "onerror"
    refute sanitized =~ "<script"
  end
end
