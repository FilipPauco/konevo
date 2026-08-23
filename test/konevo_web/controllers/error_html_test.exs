defmodule KonevoWeb.ErrorHTMLTest do
  use KonevoWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    document =
      KonevoWeb.ErrorHTML
      |> render_to_string("404", "html", [])
      |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query("svg[aria-labelledby='not-found-title']") |> Enum.any?()
    assert document |> LazyHTML.query("h1") |> LazyHTML.text() =~ "We could not find that page."
    assert document |> LazyHTML.query("a.btn-primary") |> LazyHTML.text() =~ "Go home"
  end

  test "renders 500.html" do
    document =
      KonevoWeb.ErrorHTML
      |> render_to_string("500", "html", [])
      |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query("svg[aria-labelledby='server-error-title']") |> Enum.any?()

    assert document |> LazyHTML.query("h1") |> LazyHTML.text() =~
             "Something went wrong on our side."

    assert document |> LazyHTML.query("a.btn-primary") |> LazyHTML.text() =~ "Go home"
  end
end
