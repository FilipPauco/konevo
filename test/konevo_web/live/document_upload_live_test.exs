defmodule KonevoWeb.DocumentUploadLiveTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user_with_org

  test "mounts with each document extension as an accept specifier", %{conn: conn, org: org} do
    conn = %{conn | host: "#{org.slug}.localhost"}

    {:ok, view, _html} = live(conn, ~p"/uploads/documents")

    assert has_element?(view, "#document-upload-form")

    assert has_element?(
             view,
             ~s(#document-upload-form input[type="file"][accept=".pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.csv"])
           )

    assert has_element?(view, ~s(#document-upload-form input[data-phx-auto-upload]))
    assert has_element?(view, ~s(#document-dropzone-target[for]))
    assert has_element?(view, ~s(#profile-picture-demo input[type="file"][accept="image/*"]))
    assert has_element?(view, ~s(label[for="profile-picture-demo-input"]))

    upload =
      file_input(view, "#document-upload-form", :document, [
        %{name: "slides.pptx", content: "pptx", type: "application/vnd.ms-powerpoint"}
      ])

    assert render_upload(upload, "slides.pptx") =~ "slides.pptx"
  end

  test "shows friendly feedback without a progress card for rejected files", %{
    conn: conn,
    org: org
  } do
    conn = %{conn | host: "#{org.slug}.localhost"}
    {:ok, view, _html} = live(conn, ~p"/uploads/documents")

    upload =
      file_input(view, "#document-upload-form", :document, [
        %{name: "company-logo.jpg", content: "image", type: "image/jpeg"}
      ])

    render_upload(upload, "company-logo.jpg")

    view
    |> element("#document-upload-form")
    |> render_change(%{})

    assert has_element?(view, "#flash-error")
    refute has_element?(view, "#document-dropzone-errors")
    refute has_element?(view, "#document-dropzone-entries li")
  end
end
