defmodule KonevoWeb.TestLandingLiveTest do
  use KonevoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the public product landing page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#test-landing")
    assert has_element?(view, "#test-landing-navigation")
    assert has_element?(view, "#test-landing-nav-product[type='button'][aria-current='page']")

    assert has_element?(
             view,
             "#test-landing-nav-how-it-works[type='button'][data-nav-section='#how-it-works']"
           )

    assert has_element?(
             view,
             "#test-landing-hero-how-it-works[type='button'][data-scroll-target='#how-it-works']"
           )

    assert has_element?(
             view,
             "#test-landing-nav-installation[type='button'][data-nav-section='#installation']"
           )

    assert has_element?(
             view,
             "#test-landing-nav-contact[type='button'][data-nav-section='#contact']"
           )

    assert has_element?(view, "#contact")

    refute has_element?(view, "#test-landing-contact-help")

    assert has_element?(
             view,
             "#test-landing-contact-github[href='https://github.com/FilipPauco/konevo']"
           )

    assert has_element?(view, "#test-landing-theme-toggle[type='button']")

    assert has_element?(
             view,
             "#test-landing-view-examples[href='/demo']"
           )

    assert has_element?(view, "#test-landing-hero-source-available")
    assert has_element?(view, "#product")
    assert has_element?(view, "#principles")
    assert has_element?(view, "#technology")
    assert has_element?(view, "#installation")
    assert has_element?(view, "#installation-download")
    assert has_element?(view, "#installation-configure")
    assert has_element?(view, "#installation-launch")

    assert has_element?(view, "#installation-download-code-copy[type='button']")
    assert has_element?(view, "#installation-configure-code-copy[type='button']")
    assert has_element?(view, "#installation-launch-code-copy[type='button']")

    assert has_element?(view, "#test-landing-provider-openai")
    assert has_element?(view, "#test-landing-provider-openai-models")
    assert has_element?(view, "#test-landing-provider-gmail")
    assert has_element?(view, "#test-landing-source-available")
    assert has_element?(view, "#test-landing-free-to-use")
    assert has_element?(view, "#test-landing-data-ownership")
    assert has_element?(view, "#test-landing-footer-privacy[href='/privacy']")
    assert has_element?(view, "#test-landing-footer-terms[href='/terms']")
    assert has_element?(view, "#workflow-demo-reply[data-workflow-mode='reply']")
    assert has_element?(view, "#email-to-task-flow")
    assert has_element?(view, "#email-to-task-demo")
    assert has_element?(view, "#email-to-task-demo [data-email-task-epic]")
    assert has_element?(view, "#no-reply-follow-up-flow")
    assert has_element?(view, "#no-reply-follow-up-demo")
    assert has_element?(view, "#ai-email-reply-flow")
    assert has_element?(view, "#ai-email-reply-demo")
    assert render(view) =~ "Company - Northstar"
    assert render(view) =~ "3 types ready to use"
  end

  test "the former preview URL is not routed", %{conn: conn} do
    assert conn |> get("/test") |> html_response(404)
  end

  test "renders public legal pages", %{conn: conn} do
    assert conn |> get("/privacy") |> html_response(200) =~ "Privacy Policy"
    assert conn |> get("/terms") |> html_response(200) =~ "Terms of Use"
  end
end
