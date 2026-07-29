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
