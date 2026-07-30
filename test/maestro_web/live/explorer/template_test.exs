defmodule MaestroWeb.WorkspaceLive.Explorer.TemplateTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  defp template do
    %{
      "clients" => ["http"],
      "options" => %{"method" => "POST", "url" => "https://example.com/login"},
      "payload" => %{"username" => "{{username}}"}
    }
  end

  describe "index" do
    test "lists every template in the workspace", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :template, "login_request", template())

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/templates")

      assert html =~ "login_request"
    end

    test "search filters by path/name", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :template, "login_request", template())
      resource_fixture!(workspace, :template, "logout_request", template())

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/templates")

      view |> form("#search-form", %{"query" => "login"}) |> render_change()

      assert has_element?(view, "tbody#templates a", "login_request")
      refute has_element?(view, "tbody#templates a", "logout_request")
    end

    test "paginates instead of loading every template at once", %{
      conn: conn,
      workspace: workspace
    } do
      for i <- 1..75 do
        resource_fixture!(
          workspace,
          :template,
          "template_#{String.pad_leading("#{i}", 3, "0")}",
          template()
        )
      end

      {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/templates")

      assert html =~ "Page 1 of 2 (75 total)"
      assert has_element?(view, "tbody#templates a", "template_001")
      refute has_element?(view, "tbody#templates a", "template_051")

      html = view |> element("button", "Next") |> render_click()

      assert html =~ "Page 2 of 2 (75 total)"
      assert has_element?(view, "tbody#templates a", "template_051")
      refute has_element?(view, "tbody#templates a", "template_001")
    end

    test "search resets pagination back to page 1", %{conn: conn, workspace: workspace} do
      for i <- 1..75 do
        resource_fixture!(
          workspace,
          :template,
          "template_#{String.pad_leading("#{i}", 3, "0")}",
          template()
        )
      end

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/templates")

      view |> element("button", "Next") |> render_click()
      html = view |> form("#search-form", %{"query" => "template_0"}) |> render_change()

      assert html =~ "Page 1 of 2 (75 total)"
      assert has_element?(view, "tbody#templates a", "template_001")
    end
  end

  describe "show" do
    test "renders clients/payload/options read-only", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :template, "login_request", template())

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/templates/login_request")

      assert html =~ "http"
      assert html =~ "username"
      assert html =~ "https://example.com/login"
    end

    test "shows an error state for an unknown template path", %{conn: conn, workspace: workspace} do
      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/templates/does_not_exist")

      assert html =~ "Could not load this template"
    end
  end
end
