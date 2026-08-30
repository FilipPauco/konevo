defmodule KonevoWeb.WorkflowDemoLiveTest do
  use KonevoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the public workflow demo", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/demo")

    assert has_element?(view, "#workflow-demo")
    assert has_element?(view, "#workflow-demo-navigation")
    assert has_element?(view, "#workflow-demo-navigation a[href='/#product']")
    assert has_element?(view, "#workflow-demo-navigation a[href='/#how-it-works']")
    assert has_element?(view, "#workflow-demo-navigation a[href='/#installation']")
    assert has_element?(view, "#workflow-demo-navigation a[href='/#contact']")
    assert has_element?(view, "#workflow-demo-theme-toggle[type='button']")
    assert has_element?(view, "#workflow-demo-view-examples[href='/demo'][aria-current='page']")
    assert has_element?(view, "#workflow-demo-configuration")
    assert has_element?(view, "#workflow-demo-examples")
    assert has_element?(view, "#workflow-demo-reply")
    assert has_element?(view, "#workflow-demo-task")
    assert has_element?(view, "#workflow-demo-no-reply")
    assert has_element?(view, "#workflow-demo-control a[href='/']")
    assert has_element?(view, "img[src='/images/automation_ai/settings.png']")
    assert has_element?(view, "img[src='/images/automation_ai/draft.png']")
    assert has_element?(view, "img[src='/images/automation_ai/task.png']")
    assert has_element?(view, "img[src='/images/automation_ai/no_reply.png']")
  end
end
